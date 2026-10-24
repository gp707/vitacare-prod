import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import * as bcrypt from 'bcrypt';
import { AppModule } from '../src/app.module';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { TransformInterceptor } from '../src/common/interceptors/transform.interceptor';
import { validationExceptionFactory } from '../src/common/pipes/validation-exception.factory';
import { EmailService } from '../src/email/email.service';
import { FcmService } from '../src/fcm/fcm.service';

/**
 * Admin Insights + POST /events. Runs against the real Supabase Postgres
 * instance. Uses the +91700014xxxx test phone range (distinct from every
 * other e2e suite) and its own e2e flow name for anonymous app_events rows.
 */
describe('Insights (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let adminToken: string;
  const E2E_FLOW = 'e2e_insights_flow';

  const indivPhone = (suffix: string) => `+91700014${suffix}`;
  const cgPhone = (suffix: string) => `+91700014${suffix}`;

  async function cleanup() {
    const users = `(SELECT id FROM users WHERE phone LIKE '+91700014%')`;
    await db.query(`DELETE FROM app_events WHERE flow = $1 OR user_id IN ${users}`, [E2E_FLOW]);
    await db.query(`DELETE FROM login_attempts WHERE phone LIKE '+91700014%'`);
    await db.query(`DELETE FROM jobs WHERE posted_by IN ${users}`);
    await db.query(
      `DELETE FROM care_receivers WHERE id NOT IN (SELECT care_receiver_id FROM jobs) AND created_at > NOW() - INTERVAL '1 day'
         AND id IN (SELECT id FROM care_receivers WHERE patient_name = 'Insights Patient Test')`,
    );
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN ${users} OR target_user_id IN ${users}`,
    );
    await db.query(`DELETE FROM caregiver_profiles WHERE user_id IN ${users}`);
    await db.query(`DELETE FROM individual_profiles WHERE user_id IN ${users}`);
    await db.query(`DELETE FROM users WHERE phone LIKE '+91700014%'`);
  }

  async function registerIndividual(suffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/individual')
      .send({ phone: indivPhone(suffix), full_name: 'Insights Patient', terms_accepted: true, code: '1234' })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  async function registerCaregiver(suffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: cgPhone(suffix),
        full_name: 'Insights Caregiver',
        gender: 'female',
        age: 28,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    return res.body.data as { user_id: string; profile_id: string; access_token: string };
  }

  const requirementPayload = () => ({
    care_receiver: {
      patient_name: 'Insights Patient Test',
      age: 74,
      gender: 'female',
      weight_kg: 58,
      feeding_type: 'oral_feeding',
      toilet_assistance: ['independent'],
    },
    city: 'bangalore',
    area: 'Indiranagar',
    duty_type: 'live_in',
    // Must be in the future — a fixed date goes stale and starts failing validation.
    start_date: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10),
    care_duration: 'few_weeks',
    languages: ['hindi'],
    frequency_of_care: 'daily',
    salary_amount: '1800',
  });

  async function postRequirement(token: string): Promise<string> {
    const res = await request(app.getHttpServer())
      .post('/v1/individual/requirements')
      .set('Authorization', `Bearer ${token}`)
      .send(requirementPayload());
    if (res.status !== 201) throw new Error(`POST /individual/requirements -> ${res.status}: ${JSON.stringify(res.body)}`);
    return res.body.data.id as string;
  }

  async function waitForLastSeen(userId: string): Promise<Date | null> {
    // JwtAuthGuard stamps last_seen_at fire-and-forget — poll briefly.
    for (let i = 0; i < 20; i++) {
      const r = await db.query('SELECT last_seen_at FROM users WHERE id = $1', [userId]);
      if (r.rows[0].last_seen_at && Date.now() - new Date(r.rows[0].last_seen_at).getTime() < 15_000) {
        return r.rows[0].last_seen_at;
      }
      await new Promise((resolve) => setTimeout(resolve, 150));
    }
    return null;
  }

  const adminGet = (path: string) =>
    request(app.getHttpServer()).get(`/v1/admin/insights/${path}`).set('Authorization', `Bearer ${adminToken}`);

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
      .overrideProvider(FcmService)
      .useValue({ sendToUser: jest.fn(), sendToAllCaregivers: jest.fn(), sendToTokens: jest.fn() })
      .compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
        exceptionFactory: validationExceptionFactory,
      }),
    );
    app.useGlobalFilters(new GlobalExceptionFilter());
    app.useGlobalInterceptors(new TransformInterceptor());
    await app.init();

    const passwordHash = await bcrypt.hash('AdminPass123', 4);
    await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ('insights-admin-e2e@e2e-test.local', $1, $2, 'Insights E2E Admin', 'super_admin', true)`,
      [indivPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'insights-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    adminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    try {
      await cleanup();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('access control', () => {
    it('rejects unauthenticated requests to every admin insights endpoint', async () => {
      for (const path of ['summary', 'active-users', 'inactive-since-registration', 'posters-without-accepted', 'caregivers-never-applied', 'top-actions']) {
        await request(app.getHttpServer()).get(`/v1/admin/insights/${path}`).expect(401);
      }
    });

    it('rejects a non-admin (individual) token with 403', async () => {
      const indiv = await registerIndividual('0001');
      await request(app.getHttpServer())
        .get('/v1/admin/insights/summary')
        .set('Authorization', `Bearer ${indiv.access_token}`)
        .expect(403);
    });
  });

  describe('POST /v1/events', () => {
    it('accepts an anonymous batch (pre-login screens) and stores it with no user', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/events')
        .send({
          events: [
            { kind: 'screen', flow: E2E_FLOW, screen: '/login' },
            { kind: 'tap', flow: E2E_FLOW, screen: '/login', action: 'anon_button' },
          ],
        })
        .expect(202);
      expect(res.body.data.accepted).toBe(2);
      const rows = await db.query(
        `SELECT kind, screen, action, user_id, user_role FROM app_events WHERE flow = $1 ORDER BY kind`,
        [E2E_FLOW],
      );
      expect(rows.rows).toHaveLength(2);
      expect(rows.rows.every((r) => r.user_id === null && r.user_role === null)).toBe(true);
    });

    it('attributes events to the sender (id + role) when a valid token is sent, and marks them active', async () => {
      const indiv = await registerIndividual('0002');
      await request(app.getHttpServer())
        .post('/v1/events')
        .set('Authorization', `Bearer ${indiv.access_token}`)
        .send({ events: [{ kind: 'tap', flow: E2E_FLOW, screen: '/home', action: 'authed_button' }] })
        .expect(202);
      const row = await db.query(`SELECT user_id, user_role FROM app_events WHERE action = 'authed_button'`);
      expect(row.rows[0]).toMatchObject({ user_id: indiv.user_id, user_role: 'individual' });
      expect(await waitForLastSeen(indiv.user_id)).not.toBeNull();
    });

    it('treats an invalid/garbage token as anonymous instead of failing', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/events')
        .set('Authorization', 'Bearer not.a.token')
        .send({ events: [{ kind: 'screen', flow: E2E_FLOW, screen: '/garbage-token' }] })
        .expect(202);
      expect(res.body.data.accepted).toBe(1);
    });

    it('ignores `action` on a screen view and clamps a future/ancient occurred_at to "now"', async () => {
      await request(app.getHttpServer())
        .post('/v1/events')
        .send({
          events: [
            { kind: 'screen', flow: E2E_FLOW, screen: '/clamp-future', action: 'should_be_dropped', occurred_at: '2099-01-01T00:00:00Z' },
            { kind: 'screen', flow: E2E_FLOW, screen: '/clamp-ancient', occurred_at: '2001-01-01T00:00:00Z' },
          ],
        })
        .expect(202);
      const rows = await db.query(
        `SELECT screen, action, created_at FROM app_events WHERE screen IN ('/clamp-future', '/clamp-ancient')`,
      );
      expect(rows.rows).toHaveLength(2);
      for (const row of rows.rows) {
        expect(row.action).toBeNull();
        expect(Math.abs(Date.now() - new Date(row.created_at).getTime())).toBeLessThan(60_000);
      }
    });

    it('rejects malformed batches', async () => {
      const bad = [
        { events: [] },
        { events: Array.from({ length: 26 }, () => ({ kind: 'tap', flow: E2E_FLOW, screen: '/x', action: 'a' })) },
        { events: [{ kind: 'swipe', flow: E2E_FLOW, screen: '/x' }] },
        { events: [{ kind: 'tap', flow: 'Bad Flow!', screen: '/x', action: 'a' }] },
        { events: [{ kind: 'tap', flow: E2E_FLOW, screen: '/x', action: 'has spaces' }] },
        { events: [{ kind: 'tap', flow: E2E_FLOW, screen: '/x', action: 'a', extra: 'nope' }] },
        { nope: true },
      ];
      for (const body of bad) {
        await request(app.getHttpServer()).post('/v1/events').send(body).expect(400);
      }
    });
  });

  describe('GET /v1/admin/insights/active-users', () => {
    it('lists recently active accounts with identity fields, excluding admins and honouring the window', async () => {
      const indiv = await registerIndividual('0010');
      await request(app.getHttpServer()).get('/v1/individual/me').set('Authorization', `Bearer ${indiv.access_token}`).expect(200);
      expect(await waitForLastSeen(indiv.user_id)).not.toBeNull();

      const res = await adminGet('active-users?hours=24&limit=100').expect(200);
      const mine = res.body.data.find((r: any) => r.user_id === indiv.user_id);
      expect(mine).toMatchObject({ full_name: 'Insights Patient', phone: indivPhone('0010'), role: 'individual' });
      expect(typeof mine.patient_number).toBe('number');
      expect(res.body.data.some((r: any) => r.phone === indivPhone('0999'))).toBe(false); // admin excluded
      expect(res.body.meta.total).toBeGreaterThanOrEqual(1);

      // Push their last activity 3 days back: out of the 24h/48h windows, inside 7 days.
      await db.query(`UPDATE users SET last_seen_at = NOW() - INTERVAL '3 days' WHERE id = $1`, [indiv.user_id]);
      const in24 = await adminGet('active-users?hours=24&limit=100').expect(200);
      const in48 = await adminGet('active-users?hours=48&limit=100').expect(200);
      const in168 = await adminGet('active-users?hours=168&limit=100').expect(200);
      expect(in24.body.data.some((r: any) => r.user_id === indiv.user_id)).toBe(false);
      expect(in48.body.data.some((r: any) => r.user_id === indiv.user_id)).toBe(false);
      expect(in168.body.data.some((r: any) => r.user_id === indiv.user_id)).toBe(true);
    });

    it('can be narrowed by role and rejects an invalid role/window', async () => {
      const cg = await registerCaregiver('0011');
      await db.query(`UPDATE users SET last_seen_at = NOW() WHERE id = $1`, [cg.user_id]);
      const onlyCaregivers = await adminGet('active-users?hours=24&role=caregiver&limit=100').expect(200);
      expect(onlyCaregivers.body.data.every((r: any) => r.role === 'caregiver')).toBe(true);
      expect(onlyCaregivers.body.data.some((r: any) => r.user_id === cg.user_id)).toBe(true);

      await adminGet('active-users?role=admin').expect(400);
      await adminGet('active-users?hours=0').expect(400);
      await adminGet('active-users?hours=100000').expect(400);
    });
  });

  describe('GET /v1/admin/insights/inactive-since-registration', () => {
    it('flags accounts that never came back after registering, not ones that did or are too new', async () => {
      const gone = await registerIndividual('0020');
      const returned = await registerIndividual('0021');
      const fresh = await registerIndividual('0022');
      // gone: registered 3 days ago and never seen again.
      await db.query(
        `UPDATE users SET created_at = NOW() - INTERVAL '3 days', last_seen_at = NOW() - INTERVAL '3 days' WHERE id = $1`,
        [gone.user_id],
      );
      // returned: registered 3 days ago, but active an hour ago.
      await db.query(
        `UPDATE users SET created_at = NOW() - INTERVAL '3 days', last_seen_at = NOW() - INTERVAL '1 hour' WHERE id = $1`,
        [returned.user_id],
      );
      // fresh: registered just now (younger than the 24h minimum age).
      const res = await adminGet('inactive-since-registration?min_age_hours=24&limit=100').expect(200);
      const ids = res.body.data.map((r: any) => r.user_id);
      expect(ids).toContain(gone.user_id);
      expect(ids).not.toContain(returned.user_id);
      expect(ids).not.toContain(fresh.user_id);
      // Oldest registrations first.
      const registered = res.body.data.map((r: any) => new Date(r.created_at).getTime());
      expect([...registered].sort((a, b) => a - b)).toEqual(registered);
    });
  });

  describe('GET /v1/admin/insights/caregivers-never-applied', () => {
    it('lists a registered caregiver until they apply to something', async () => {
      const poster = await registerIndividual('0030');
      const jobId = await postRequirement(poster.access_token);
      const cg = await registerCaregiver('0031');

      const before = await adminGet('caregivers-never-applied?limit=100').expect(200);
      const entry = before.body.data.find((r: any) => r.user_id === cg.user_id);
      expect(entry).toMatchObject({ phone: cgPhone('0031'), role: 'caregiver', verification_status: 'pending_call' });
      expect(typeof entry.caregiver_number).toBe('number');

      await db.query(
        `INSERT INTO job_applications (job_id, profile_id, status, applied_at) VALUES ($1, $2, 'applied', NOW())`,
        [jobId, cg.profile_id],
      );
      const after = await adminGet('caregivers-never-applied?limit=100').expect(200);
      expect(after.body.data.some((r: any) => r.user_id === cg.user_id)).toBe(false);
    });
  });

  describe('GET /v1/admin/insights/posters-without-accepted', () => {
    it('lists a poster whose applicants were never accepted, with counts, and drops them once one is accepted', async () => {
      const poster = await registerIndividual('0040');
      const jobId = await postRequirement(poster.access_token);
      const cgA = await registerCaregiver('0041');
      const cgB = await registerCaregiver('0042');
      const noApplicants = await registerIndividual('0043');
      await postRequirement(noApplicants.access_token);

      await db.query(
        `INSERT INTO job_applications (job_id, profile_id, status, applied_at) VALUES ($1, $2, 'applied', NOW()), ($1, $3, 'rejected', NOW())`,
        [jobId, cgA.profile_id, cgB.profile_id],
      );

      const res = await adminGet('posters-without-accepted?limit=100').expect(200);
      const entry = res.body.data.find((r: any) => r.user_id === poster.user_id);
      expect(entry).toMatchObject({
        phone: indivPhone('0040'),
        role: 'individual',
        postings: 1,
        applicants: 2,
        pending_applicants: 1,
      });
      expect(typeof entry.patient_number).toBe('number');
      // A poster nobody applied to is a different problem — not listed here.
      expect(res.body.data.some((r: any) => r.user_id === noApplicants.user_id)).toBe(false);

      await db.query(`UPDATE job_applications SET status = 'accepted' WHERE job_id = $1 AND profile_id = $2`, [
        jobId,
        cgA.profile_id,
      ]);
      const after = await adminGet('posters-without-accepted?limit=100').expect(200);
      expect(after.body.data.some((r: any) => r.user_id === poster.user_id)).toBe(false);
    });
  });

  describe('GET /v1/admin/insights/top-actions + summary', () => {
    it('ranks buttons by tap count with unique users, separately from screen views', async () => {
      const a = await registerIndividual('0050');
      const b = await registerIndividual('0051');
      const tap = (token: string, action: string, times: number) =>
        request(app.getHttpServer())
          .post('/v1/events')
          .set('Authorization', `Bearer ${token}`)
          .send({ events: Array.from({ length: times }, () => ({ kind: 'tap', flow: E2E_FLOW, screen: '/top', action })) })
          .expect(202);
      await tap(a.access_token, 'most_clicked', 3);
      await tap(b.access_token, 'most_clicked', 2);
      await tap(a.access_token, 'least_clicked', 1);
      await request(app.getHttpServer())
        .post('/v1/events')
        .send({ events: [{ kind: 'screen', flow: E2E_FLOW, screen: '/viewed-screen' }] })
        .expect(202);

      const taps = await adminGet(`top-actions?kind=tap&flow=${E2E_FLOW}`).expect(200);
      expect(taps.body.data[0]).toMatchObject({ action: 'most_clicked', count: 5, unique_users: 2, flow: E2E_FLOW });
      expect(taps.body.data.map((r: any) => r.action)).toContain('least_clicked');
      expect(taps.body.data.every((r: any) => r.kind === 'tap')).toBe(true);

      const screens = await adminGet(`top-actions?kind=screen&flow=${E2E_FLOW}`).expect(200);
      expect(screens.body.data.some((r: any) => r.screen === '/viewed-screen')).toBe(true);
      expect(screens.body.data.every((r: any) => r.kind === 'screen')).toBe(true);

      await adminGet('top-actions?kind=hover').expect(400);
      await adminGet('top-actions?flow=Bad%20Flow').expect(400);
      await adminGet('top-actions?days=0').expect(400);
    });

    it('returns every headline count as a number', async () => {
      const res = await adminGet('summary').expect(200);
      for (const key of [
        'active_users_24h',
        'active_users_48h',
        'active_users_7d',
        'inactive_since_registration',
        'posters_without_accepted',
        'caregivers_never_applied',
      ]) {
        expect(typeof res.body.data[key]).toBe('number');
      }
      expect(res.body.data.active_users_24h).toBeLessThanOrEqual(res.body.data.active_users_48h);
      expect(res.body.data.active_users_48h).toBeLessThanOrEqual(res.body.data.active_users_7d);
    });
  });

  describe('GET /v1/admin/insights/login-problems', () => {
    jest.setTimeout(60_000); // these tests make several real logins + wait for async writes
    const login = (phone: string, code: string, appName: 'nursenow' | 'nursejobs') =>
      request(app.getHttpServer()).post('/v1/auth/login/code').send({ phone, code, app: appName });
    // The recorder is fire-and-forget (it must never slow or break a login),
    // so the row can land a few ms after the HTTP response: wait for it.
    // [expected] undefined = just give any in-flight write a moment, for the
    // "nothing should have been recorded" assertions.
    const attempts = async (phone: string, expected?: number) => {
      const read = async () =>
        (await db.query('SELECT reason, app, method, user_id FROM login_attempts WHERE phone = $1 ORDER BY created_at', [phone])).rows;
      for (let i = 0; i < 40; i++) {
        const rows = await read();
        if (expected !== undefined && rows.length >= expected) return rows;
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      return read();
    };
    const problems = (query = '') => adminGet(`login-problems?limit=100${query}`);

    it('records wrong PINs, lists the person with attempt counts and identity, and never stores the PIN', async () => {
      const patient = await registerIndividual('0060');
      await login(indivPhone('0060'), '9999', 'nursenow').expect(401);
      await login(indivPhone('0060'), '8888', 'nursenow').expect(401);

      const rows = await attempts(indivPhone('0060'), 2);
      expect(rows.map((r) => r.reason)).toEqual(['wrong_pin', 'wrong_pin']);
      expect(rows.every((r) => r.user_id === patient.user_id && r.method === 'code' && r.app === 'nursenow')).toBe(true);
      const stored = JSON.stringify((await db.query('SELECT * FROM login_attempts WHERE phone = $1', [indivPhone('0060')])).rows);
      expect(stored).not.toContain('9999');
      expect(stored).not.toContain('8888');

      const res = await problems().expect(200);
      const entry = res.body.data.find((r: any) => r.phone === indivPhone('0060'));
      expect(entry).toMatchObject({
        full_name: 'Insights Patient',
        role: 'individual',
        attempts: 2,
        wrong_pin_attempts: 2,
        last_reason: 'wrong_pin',
        last_app: 'nursenow',
        status: 'locked_out',
        user_id: patient.user_id,
      });
      expect(typeof entry.patient_number).toBe('number');
      expect(res.body.meta.total).toBe(res.body.data.length);
    });

    it('moves a person to "recovered" once they get in, and the default list stops showing them', async () => {
      await registerIndividual('0061');
      await login(indivPhone('0061'), '0000', 'nursenow').expect(401);
      await attempts(indivPhone('0061'), 1);
      expect((await problems().expect(200)).body.data.some((r: any) => r.phone === indivPhone('0061'))).toBe(true);

      await login(indivPhone('0061'), '1234', 'nursenow').expect(200);

      const locked = await problems().expect(200);
      expect(locked.body.data.some((r: any) => r.phone === indivPhone('0061'))).toBe(false);
      const recovered = await problems('&status=recovered').expect(200);
      expect(recovered.body.data.find((r: any) => r.phone === indivPhone('0061'))).toMatchObject({ status: 'recovered', attempts: 1 });
      const all = await problems('&status=all').expect(200);
      expect(all.body.data.some((r: any) => r.phone === indivPhone('0061'))).toBe(true);
    });

    it('records a number with no account at all, with no identity — and drops it to recovered once they register', async () => {
      const phone = indivPhone('0062');
      await login(phone, '1234', 'nursenow').expect(404);
      expect((await attempts(phone, 1)).map((r) => r.reason)).toEqual(['unknown_account']);

      const entry = (await problems().expect(200)).body.data.find((r: any) => r.phone === phone);
      expect(entry).toMatchObject({ last_reason: 'unknown_account', status: 'locked_out', user_id: null, full_name: null });

      // They then register — whatever was wrong has been dealt with.
      await registerIndividual('0062');
      const after = await problems('&status=recovered').expect(200);
      expect(after.body.data.find((r: any) => r.phone === phone)).toMatchObject({ status: 'recovered' });
    });

    it('does NOT count a caregiver\'s normal login (the patient/organisation leg misses first, then the caregiver one succeeds)', async () => {
      await registerCaregiver('0063');
      // JustHeal\'s single login screen: nursenow first (no account -> 404)...
      await login(cgPhone('0063'), '1234', 'nursenow').expect(404);
      // ...then the caregiver bucket, which succeeds.
      await login(cgPhone('0063'), '1234', 'nursejobs').expect(200);
      expect(await attempts(cgPhone('0063'))).toHaveLength(0); // waits ~4s for any (wrongly) in-flight write
    });

    it('does count a caregiver who then gets their PIN wrong on the caregiver leg', async () => {
      const cg = await registerCaregiver('0064');
      await login(cgPhone('0064'), '1234', 'nursenow').expect(404); // fallback leg, not recorded
      await login(cgPhone('0064'), '7777', 'nursejobs').expect(401);
      const rows = await attempts(cgPhone('0064'), 1);
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({ reason: 'wrong_pin', app: 'nursejobs', user_id: cg.user_id });
      const entry = (await problems().expect(200)).body.data.find((r: any) => r.phone === cgPhone('0064'));
      expect(entry).toMatchObject({ role: 'caregiver', status: 'locked_out' });
      expect(typeof entry.caregiver_number).toBe('number');
    });

    it('records "wrong login type" when a patient number is used on the caregiver login', async () => {
      const patient = await registerIndividual('0065');
      await login(indivPhone('0065'), '1234', 'nursejobs').expect(404);
      const rows = await attempts(indivPhone('0065'), 1);
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({ reason: 'wrong_app', app: 'nursejobs', user_id: patient.user_id });
    });

    it('records a deactivated account and keeps it locked out', async () => {
      const patient = await registerIndividual('0066');
      await db.query('UPDATE users SET is_active = false WHERE id = $1', [patient.user_id]);
      await login(indivPhone('0066'), '1234', 'nursenow').expect(401);
      await attempts(indivPhone('0066'), 1);
      const entry = (await problems().expect(200)).body.data.find((r: any) => r.phone === indivPhone('0066'));
      expect(entry).toMatchObject({ last_reason: 'account_deactivated', status: 'locked_out', is_active: false });
    });

    it('only looks back over the requested window', async () => {
      await registerIndividual('0067');
      await login(indivPhone('0067'), '0000', 'nursenow').expect(401);
      await attempts(indivPhone('0067'), 1);
      await db.query(`UPDATE login_attempts SET created_at = NOW() - INTERVAL '10 days' WHERE phone = $1`, [indivPhone('0067')]);
      // status=all: backdating the failure to before this account registered makes it count as
      // "recovered" (they registered afterwards), which is not what this test is about.
      expect((await problems('&days=7&status=all').expect(200)).body.data.some((r: any) => r.phone === indivPhone('0067'))).toBe(false);
      expect((await problems('&days=14&status=all').expect(200)).body.data.some((r: any) => r.phone === indivPhone('0067'))).toBe(true);
    });

    it('is admin-only and validates its parameters', async () => {
      await request(app.getHttpServer()).get('/v1/admin/insights/login-problems').expect(401);
      const patient = await registerIndividual('0068');
      await request(app.getHttpServer())
        .get('/v1/admin/insights/login-problems')
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(403);
      await problems('&days=0').expect(400);
      await problems('&days=31').expect(400);
      await problems('&status=weird').expect(400);
    });

    it('feeds the summary count of people still locked out', async () => {
      const summary = await adminGet('summary').expect(200);
      expect(typeof summary.body.data.login_problems).toBe('number');
      const list = await problems().expect(200);
      expect(summary.body.data.login_problems).toBe(list.body.meta.total);
    });
  });
});
