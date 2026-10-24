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
});
