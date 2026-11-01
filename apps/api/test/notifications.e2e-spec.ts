import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import * as bcrypt from 'bcrypt';
import { AppModule } from '../src/app.module';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { TransformInterceptor } from '../src/common/interceptors/transform.interceptor';
import { validationExceptionFactory } from '../src/common/pipes/validation-exception.factory';
import { UsersRepository } from '../src/database/repositories/users.repository';
import { EmailService } from '../src/email/email.service';
import { FcmService } from '../src/fcm/fcm.service';
import { DutyRemindersService } from '../src/notifications/duty-reminders.service';
import { NoApplicantsNudgeService } from '../src/notifications/no-applicants-nudge.service';

/**
 * Who gets which push, against the real database (the FCM sender is mocked, so
 * nothing is actually delivered). Uses the +91700016xxxx phone range, distinct
 * from every other e2e suite.
 */
// Every e2e suite here talks to the app over a fresh supertest connection, and
// roughly one run in a few sees "socket hang up" / "Parse Error: Expected HTTP/"
// from the client side (no server error is logged; it also happens in the
// older suites). Retry once so a dropped connection is not mistaken for a
// failing assertion — a genuine assertion failure fails twice and still shows.
jest.retryTimes(1, { logErrorsBeforeRetry: true });

describe('Push notifications (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let fcm: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };

  const phone = (suffix: string) => `+91700016${suffix}`;
  const START_DATE = '2030-06-10'; // day duty -> starts 08:00 IST
  const ist = (iso: string) => new Date(`${iso}+05:30`);

  async function cleanup() {
    const mine = "(SELECT id FROM users WHERE phone LIKE '+91700016%')";
    await db.query(`DELETE FROM job_applications WHERE job_id IN (SELECT id FROM jobs WHERE posted_by IN ${mine})`);
    const cr = await db.query(`SELECT care_receiver_id FROM jobs WHERE posted_by IN ${mine}`);
    await db.query(`DELETE FROM jobs WHERE posted_by IN ${mine}`);
    if (cr.rows.length) {
      await db.query('DELETE FROM care_receivers WHERE id = ANY($1)', [cr.rows.map((r) => r.care_receiver_id)]);
    }
    await db.query(
      `DELETE FROM organisation_requirement_applications WHERE requirement_id IN
         (SELECT id FROM organisation_requirements WHERE posted_by IN ${mine})`,
    );
    await db.query(`DELETE FROM organisation_requirements WHERE posted_by IN ${mine}`);
    await db.query(`DELETE FROM organisation_profiles WHERE user_id IN ${mine}`);
    await db.query(`DELETE FROM audit_logs WHERE user_id IN ${mine} OR target_user_id IN ${mine}`);
    await db.query(`DELETE FROM login_attempts WHERE phone LIKE '+91700016%'`);
    await db.query(`DELETE FROM individual_profiles WHERE user_id IN ${mine}`);
    await db.query(`DELETE FROM caregiver_profiles WHERE user_id IN ${mine}`);
    await db.query("DELETE FROM users WHERE phone LIKE '+91700016%'");
  }

  async function registerCaregiver(suffix: string, gender: 'female' | 'male' = 'female') {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: phone(suffix),
        full_name: 'Notify Caregiver',
        gender,
        age: 28,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    const c = res.body.data as { user_id: string; profile_id: string; access_token: string };
    await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [c.user_id]);
    return c;
  }

  async function registerIndividual(suffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/individual')
      .send({ phone: phone(suffix), full_name: 'Notify Patient', terms_accepted: true, code: '1234' })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  const requirementPayload = (overrides: Record<string, unknown> = {}) => ({
    care_receiver: {
      patient_name: 'Notify Patient',
      age: 74,
      gender: 'female',
      weight_kg: 58,
      feeding_type: 'oral_feeding',
      toilet_assistance: ['independent'],
    },
    city: 'bangalore',
    area: 'Indiranagar',
    duty_type: 'day_duty',
    start_date: START_DATE,
    care_duration: 'few_weeks',
    languages: ['hindi'],
    frequency_of_care: 'daily',
    salary_amount: '1800',
    ...overrides,
  });

  async function postAndApproveRequirement(individual: { access_token: string }, overrides = {}) {
    const created = await request(app.getHttpServer())
      .post('/v1/individual/requirements')
      .set('Authorization', `Bearer ${individual.access_token}`)
      .send(requirementPayload(overrides))
      .expect(201);
    const jobId = created.body.data.id as string;
    await request(app.getHttpServer())
      .patch(`/v1/admin/jobs/${jobId}/approve`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .expect(200);
    return jobId;
  }

  const pushesTo = (userId: string) => fcm.sendToUser.mock.calls.filter((c) => c[0] === userId);

  /** Pushes are fire-and-forget by design (they must never slow or fail the
   *  action that triggers them), so the HTTP response can return first. Waits
   *  until no new push has arrived for a moment before a test looks. */
  async function settled() {
    let last = -1;
    for (let i = 0; i < 40; i++) {
      await new Promise((resolve) => setTimeout(resolve, 60));
      const now = fcm.sendToUser.mock.calls.length;
      if (now === last) return;
      last = now;
    }
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

    fcm = { sendToUser: jest.fn().mockResolvedValue(undefined), sendToAllCaregivers: jest.fn() };
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
      .overrideProvider(FcmService)
      .useValue(fcm)
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

    await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ('notify-admin-e2e@e2e-test.local', $1, $2, 'Notify E2E Admin', 'super_admin', true)`,
      [phone('0999'), await bcrypt.hash('AdminPass123', 4)],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'notify-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  beforeEach(() => fcm.sendToUser.mockClear());

  describe('devices', () => {
    it('welcomes a new caregiver once, and a second device or a re-login adds no second welcome', async () => {
      const cg = await registerCaregiver('0001');
      const put = (token: string) =>
        request(app.getHttpServer())
          .put('/v1/caregiver/fcm-token')
          .set('Authorization', `Bearer ${cg.access_token}`)
          .send({ token })
          .expect(200);

      await put('device-A');
      await settled();
      expect(pushesTo(cg.user_id)).toHaveLength(1);
      await settled();
      expect(pushesTo(cg.user_id)[0][1]).toBe('Registration received');
      await settled();
      expect(pushesTo(cg.user_id)[0][3]).toEqual({ route: '/caregiver/profile' });

      await put('device-B'); // a second phone
      await put('device-A'); // the app re-registers on every launch
      await settled();
      expect(pushesTo(cg.user_id)).toHaveLength(1);

      const devices = await db.query('SELECT token FROM user_fcm_tokens WHERE user_id = $1 ORDER BY token', [cg.user_id]);
      expect(devices.rows.map((r) => r.token)).toEqual(['device-A', 'device-B']);
    });

    it('moves a device to whoever registers it next, and logout removes only the caller’s own copy', async () => {
      const first = await registerCaregiver('0002');
      const second = await registerIndividual('0003');
      const as = (u: { access_token: string }) => ({ Authorization: `Bearer ${u.access_token}` });

      await request(app.getHttpServer()).put('/v1/caregiver/fcm-token').set(as(first)).send({ token: 'shared-phone' }).expect(200);
      // Someone else signs in on the same phone.
      await request(app.getHttpServer()).put('/v1/individual/profile/fcm-token').set(as(second)).send({ token: 'shared-phone' }).expect(200);

      const owner = await db.query('SELECT user_id FROM user_fcm_tokens WHERE token = $1', ['shared-phone']);
      expect(owner.rows).toEqual([{ user_id: second.user_id }]);

      // The first account trying to "log out" that device must not remove the new owner's.
      await request(app.getHttpServer()).delete('/v1/caregiver/fcm-token').set(as(first)).send({ token: 'shared-phone' }).expect(200);
      expect((await db.query('SELECT 1 FROM user_fcm_tokens WHERE token = $1', ['shared-phone'])).rowCount).toBe(1);

      await request(app.getHttpServer()).delete('/v1/individual/profile/fcm-token').set(as(second)).send({ token: 'shared-phone' }).expect(200);
      expect((await db.query('SELECT 1 FROM user_fcm_tokens WHERE token = $1', ['shared-phone'])).rowCount).toBe(0);
    });

    it('only targets caregivers an employer’s gender preference allows', async () => {
      const women = await registerCaregiver('0004', 'female');
      const men = await registerCaregiver('0005', 'male');
      for (const [c, token] of [[women, 'tok-woman'], [men, 'tok-man']] as const) {
        await request(app.getHttpServer())
          .put('/v1/caregiver/fcm-token')
          .set('Authorization', `Bearer ${c.access_token}`)
          .send({ token })
          .expect(200);
      }
      const users = app.get(UsersRepository);
      const forFemaleOnly = await users.listCaregiverFcmTokens('female');
      expect(forFemaleOnly).toContain('tok-woman');
      expect(forFemaleOnly).not.toContain('tok-man');
      const noPreference = await users.listCaregiverFcmTokens(null);
      expect(noPreference).toEqual(expect.arrayContaining(['tok-woman', 'tok-man']));
    });
  });

  describe('a patient’s requirement', () => {
    it('tells the patient when admin approves it, and when admin rejects it', async () => {
      const patient = await registerIndividual('0010');
      const approvedId = await postAndApproveRequirement(patient);
      await settled();
      const approved = pushesTo(patient.user_id).find((c) => c[1] === 'Your requirement is live');
      expect(approved).toBeDefined();
      expect(approved![3]).toEqual({ route: '/home' });
      expect(approved![2]).toMatch(/PAT-JOB-\d+/);

      const other = await registerIndividual('0011');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${other.access_token}`)
        .send(requirementPayload())
        .expect(201);
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${created.body.data.id}/reject`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ reason: 'Details unclear' })
        .expect(200);
      await settled();
      const rejected = pushesTo(other.user_id).find((c) => c[1] === 'Requirement not approved');
      expect(rejected![2]).toContain('Details unclear');
      expect(approvedId).toBeTruthy();
    });

    it('announces an applicant to the patient once per burst, and the accept/decline reach the caregiver', async () => {
      const patient = await registerIndividual('0012');
      const jobId = await postAndApproveRequirement(patient);
      const cg1 = await registerCaregiver('0013');
      const cg2 = await registerCaregiver('0014');
      fcm.sendToUser.mockClear();

      const apply = (c: { access_token: string }) =>
        request(app.getHttpServer())
          .post(`/v1/caregiver/jobs/${jobId}/apply`)
          .set('Authorization', `Bearer ${c.access_token}`)
          .send({ status: 'applied' })
          .expect(200);

      await apply(cg1);
      await apply(cg2); // same burst: no second push
      await settled();
      const toPatient = pushesTo(patient.user_id);
      expect(toPatient).toHaveLength(1);
      expect(toPatient[0][1]).toBe('A caregiver applied');
      expect(toPatient[0][3]).toEqual({ route: '/home' });

      const applications = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(200);
      const idFor = (profileId: string) =>
        applications.body.data.find((a: { profile_id: string }) => a.profile_id === profileId).id as string;

      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${idFor(cg2.profile_id)}`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .send({ status: 'rejected', reason: 'Found someone closer' })
        .expect(200);
      await settled();
      const declined = pushesTo(cg2.user_id)[0];
      expect(declined[1]).toBe('Application update');
      expect(declined[2]).toContain('Found someone closer');
      expect(declined[3]).toEqual({ route: '/caregiver/jobs' });

      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${idFor(cg1.profile_id)}`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);
      await settled();
      const accepted = pushesTo(cg1.user_id)[0];
      expect(accepted[1]).toBe("You've been accepted");
      expect(accepted[3]).toEqual({ route: '/caregiver/my-jobs' });
    });
  });

  describe('duty-start reminders for an accepted caregiver', () => {
    async function acceptedCaregiver(suffixes: [string, string]) {
      const patient = await registerIndividual(suffixes[0]);
      const jobId = await postAndApproveRequirement(patient);
      const cg = await registerCaregiver(suffixes[1]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      const apps = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(200);
      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${apps.body.data[0].id}`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);
      return { patient, jobId, cg };
    }

    it('sends 2 days, then 1 day, then "soon — do not forget", each exactly once', async () => {
      const { cg } = await acceptedCaregiver(['0020', '0021']);
      const sweeper = app.get(DutyRemindersService);
      fcm.sendToUser.mockClear();

      await sweeper.sweep(ist('2030-06-08T16:00:00')); // 40h before
      await sweeper.sweep(ist('2030-06-08T16:15:00')); // same band again: nothing new
      await settled();
      expect(pushesTo(cg.user_id).map((c) => c[1])).toEqual(['Duty in 2 days']);

      await sweeper.sweep(ist('2030-06-09T12:00:00')); // 20h before
      await settled();
      expect(pushesTo(cg.user_id).map((c) => c[1])).toEqual(['Duty in 2 days', 'Duty in 1 day']);

      await sweeper.sweep(ist('2030-06-09T20:30:00')); // 11.5h before
      await settled();
      const all = pushesTo(cg.user_id);
      expect(all.map((c) => c[1])).toEqual(['Duty in 2 days', 'Duty in 1 day', 'Duty starting soon']);
      expect(all[2][2]).toContain('Do not forget');
      expect(all[2][3]).toEqual({ route: '/caregiver/my-jobs' });

      await sweeper.sweep(ist('2030-06-09T21:00:00'));
      await sweeper.sweep(ist('2030-06-10T09:00:00')); // already started
      await settled();
      expect(pushesTo(cg.user_id)).toHaveLength(3);
    });

    it('does not remind a caregiver whose acceptance was undone, and starts fresh if they are accepted again', async () => {
      const { patient, jobId, cg } = await acceptedCaregiver(['0022', '0023']);
      const sweeper = app.get(DutyRemindersService);
      const apps = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(200);
      const appId = apps.body.data[0].id as string;
      const decide = (body: object) =>
        request(app.getHttpServer())
          .patch(`/v1/individual/requirements/${jobId}/applications/${appId}`)
          .set('Authorization', `Bearer ${patient.access_token}`)
          .send(body)
          .expect(200);

      fcm.sendToUser.mockClear();
      await sweeper.sweep(ist('2030-06-08T16:00:00'));
      await settled();
      expect(pushesTo(cg.user_id).filter((c) => c[1] === 'Duty in 2 days')).toHaveLength(1);

      await decide({ status: 'rejected', reason: 'Changed plans' });
      fcm.sendToUser.mockClear();
      await sweeper.sweep(ist('2030-06-09T12:00:00'));
      await settled();
      expect(pushesTo(cg.user_id).filter((c) => String(c[1]).startsWith('Duty'))).toHaveLength(0);

      await decide({ status: 'accepted' }); // re-accepted: the cycle restarts
      fcm.sendToUser.mockClear();
      await sweeper.sweep(ist('2030-06-08T16:00:00'));
      await settled();
      expect(pushesTo(cg.user_id).filter((c) => c[1] === 'Duty in 2 days')).toHaveLength(1);
    });

    it('two instances sweeping at the same moment send each reminder only once', async () => {
      const { cg } = await acceptedCaregiver(['0024', '0025']);
      const sweeper = app.get(DutyRemindersService);
      fcm.sendToUser.mockClear();
      await Promise.all([sweeper.sweep(ist('2030-06-08T16:00:00')), sweeper.sweep(ist('2030-06-08T16:00:00'))]);
      await settled();
      expect(pushesTo(cg.user_id).filter((c) => c[1] === 'Duty in 2 days')).toHaveLength(1);
    });

    it('sends fresh reminders when the patient moves the start date', async () => {
      const { patient, jobId, cg } = await acceptedCaregiver(['0026', '0027']);
      const sweeper = app.get(DutyRemindersService);
      await sweeper.sweep(ist('2030-06-08T16:00:00'));
      fcm.sendToUser.mockClear();

      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .send(requirementPayload({ start_date: '2030-06-15' }))
        .expect(200);

      await sweeper.sweep(ist('2030-06-13T16:00:00')); // 40h before the new 15th 08:00
      // The edit itself tells the caregiver the job changed; the fresh countdown follows.
      await settled();
      expect(pushesTo(cg.user_id).map((c) => c[1])).toEqual(['Job updated', 'Duty in 2 days']);
    });

    it('holds routine reminders overnight', async () => {
      const { cg } = await acceptedCaregiver(['0028', '0029']);
      const sweeper = app.get(DutyRemindersService);
      fcm.sendToUser.mockClear();
      await sweeper.sweep(ist('2030-06-08T23:30:00')); // 32.5h before, but it is night
      await settled();
      expect(pushesTo(cg.user_id)).toHaveLength(0);
    });
  });

  // ── Changes to a posting, and account blocks ──────────────────────────────

  async function acceptedPair(suffixes: [string, string]) {
    const patient = await registerIndividual(suffixes[0]);
    const jobId = await postAndApproveRequirement(patient);
    const cg = await registerCaregiver(suffixes[1]);
    await request(app.getHttpServer())
      .post(`/v1/caregiver/jobs/${jobId}/apply`)
      .set('Authorization', `Bearer ${cg.access_token}`)
      .send({ status: 'applied' })
      .expect(200);
    const apps = await request(app.getHttpServer())
      .get(`/v1/individual/requirements/${jobId}/applications`)
      .set('Authorization', `Bearer ${patient.access_token}`)
      .expect(200);
    const applicationId = apps.body.data[0].id as string;
    const accept = () =>
      request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);
    return { patient, jobId, cg, applicationId, accept };
  }

  describe('a posting changes under its caregivers', () => {
    it('tells the patient when the accepted caregiver closes the job out', async () => {
      const { patient, jobId, cg, accept } = await acceptedPair(['0030', '0031']);
      await accept();
      fcm.sendToUser.mockClear();

      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/complete`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({})
        .expect(200);

      await settled();
      const push = pushesTo(patient.user_id).find((c) => c[1] === 'A caregiver closed the job');
      expect(push).toBeDefined();
      expect(push![2]).toContain('open for new applicants again');
      expect(push![3]).toEqual({ route: '/home' });
    });

    it('tells a waiting and an accepted caregiver when the patient changes the salary, but not for an unrelated edit', async () => {
      const { patient, jobId, cg } = await acceptedPair(['0032', '0033']);
      fcm.sendToUser.mockClear();
      const edit = (overrides: Record<string, unknown>) =>
        request(app.getHttpServer())
          .patch(`/v1/individual/requirements/${jobId}`)
          .set('Authorization', `Bearer ${patient.access_token}`)
          .send(requirementPayload(overrides))
          .expect(200);

      await edit({ salary_amount: '2500' });
      await settled();
      const updated = pushesTo(cg.user_id).filter((c) => c[1] === 'Job updated');
      expect(updated).toHaveLength(1);
      expect(updated[0][3]).toEqual({ route: '/caregiver/jobs' }); // still just applied

      fcm.sendToUser.mockClear();
      await edit({ salary_amount: '2500' }); // identical re-save: nothing changed
      await settled();
      expect(pushesTo(cg.user_id).filter((c) => c[1] === 'Job updated')).toHaveLength(0);
    });

    it('sends an accepted caregiver to MyJobs when the job is changed', async () => {
      const { patient, jobId, cg, accept } = await acceptedPair(['0034', '0035']);
      await accept();
      fcm.sendToUser.mockClear();
      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .send(requirementPayload({ area: 'Whitefield' }))
        .expect(200);
      await settled();
      const push = pushesTo(cg.user_id).find((c) => c[1] === 'Job updated');
      expect(push![3]).toEqual({ route: '/caregiver/my-jobs' });
    });

    it('tells everyone involved when the patient cancels', async () => {
      const { patient, jobId, cg, accept } = await acceptedPair(['0036', '0037']);
      await accept();
      fcm.sendToUser.mockClear();

      await request(app.getHttpServer())
        .post(`/v1/individual/requirements/${jobId}/cancel`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(200);

      await settled();
      const push = pushesTo(cg.user_id).find((c) => c[1] === 'Job cancelled');
      expect(push).toBeDefined();
      expect(push![3]).toEqual({ route: '/caregiver/jobs' });
    });

    it('tells caregivers still waiting when admin closes the job', async () => {
      const patient = await registerIndividual('0038');
      const jobId = await postAndApproveRequirement(patient);
      const cg = await registerCaregiver('0039');
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      fcm.sendToUser.mockClear();

      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}/close`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      await settled();
      expect(pushesTo(cg.user_id).map((c) => c[1])).toEqual(['Job closed']);
    });
  });

  describe('admin blocks and unblocks an account', () => {
    it('tells a patient when posting is blocked and when it is restored', async () => {
      const patient = await registerIndividual('0040');
      const call = (action: 'block' | 'unblock', body: object) =>
        request(app.getHttpServer())
          .patch(`/v1/admin/individuals/${patient.user_id}/${action}`)
          .set('Authorization', `Bearer ${superAdminToken}`)
          .send(body)
          .expect(200);
      fcm.sendToUser.mockClear();

      await call('block', { level: 'job_posting', reason: 'spam' });
      await call('unblock', { level: 'job_posting' });

      await settled();
      expect(pushesTo(patient.user_id).map((c) => [c[1], c[3]])).toEqual([
        ['Posting paused', { route: '/home' }],
        ['Posting restored', { route: '/home' }],
      ]);
    });

    it('delivers a full block BEFORE the account is switched off, and tells them when it is restored', async () => {
      const patient = await registerIndividual('0041');
      fcm.sendToUser.mockClear();
      let activeWhenSent: boolean | undefined;
      fcm.sendToUser.mockImplementationOnce(async () => {
        const row = await db.query('SELECT is_active FROM users WHERE id = $1', [patient.user_id]);
        activeWhenSent = row.rows[0].is_active;
      });

      await request(app.getHttpServer())
        .patch(`/v1/admin/individuals/${patient.user_id}/block`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'full', reason: 'abuse' })
        .expect(200);

      expect(activeWhenSent).toBe(true); // sent while the account could still receive it
      const after = await db.query('SELECT is_active FROM users WHERE id = $1', [patient.user_id]);
      expect(after.rows[0].is_active).toBe(false);

      await request(app.getHttpServer())
        .patch(`/v1/admin/individuals/${patient.user_id}/unblock`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'full' })
        .expect(200);
      await settled();
      expect(pushesTo(patient.user_id).map((c) => c[1])).toEqual(['Account blocked', 'Account restored']);
    });
  });

  describe('no applicants after 3 days', () => {
    const ageJob = (jobId: string, days: number) =>
      db.query("UPDATE jobs SET posted_at = NOW() - make_interval(days => $2) WHERE id = $1", [jobId, days]);
    const inWindow = () => ist('2030-06-05T11:00:00');

    it('nudges a patient once, only after 3 days, and never when someone applied or at night', async () => {
      const lonely = await registerIndividual('0050');
      const lonelyJob = await postAndApproveRequirement(lonely);
      const popular = await registerIndividual('0051');
      const popularJob = await postAndApproveRequirement(popular);
      const cg = await registerCaregiver('0052');
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${popularJob}/apply`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      const sweeper = app.get(NoApplicantsNudgeService);
      fcm.sendToUser.mockClear();

      await sweeper.sweep(inWindow()); // too new
      await settled();
      expect(pushesTo(lonely.user_id)).toHaveLength(0);

      await ageJob(lonelyJob, 4);
      await ageJob(popularJob, 4);
      await sweeper.sweep(ist('2030-06-05T23:00:00')); // night: held
      await settled();
      expect(pushesTo(lonely.user_id)).toHaveLength(0);

      await sweeper.sweep(inWindow());
      await sweeper.sweep(inWindow()); // second sweep: already nudged
      await settled();
      const nudges = pushesTo(lonely.user_id);
      expect(nudges).toHaveLength(1);
      expect(nudges[0][1]).toBe('No applicants yet');
      expect(nudges[0][3]).toEqual({ route: '/home' });
      // Someone applied, so no nudge (only the "a caregiver applied" push it already got).
      await settled();
      expect(pushesTo(popular.user_id).filter((c) => c[1] === 'No applicants yet')).toHaveLength(0);
    });

    it('nudges again only after the requirement is reposted and waits another 3 days', async () => {
      const patient = await registerIndividual('0053');
      const jobId = await postAndApproveRequirement(patient);
      const sweeper = app.get(NoApplicantsNudgeService);
      await ageJob(jobId, 4);
      fcm.sendToUser.mockClear();
      await sweeper.sweep(inWindow());
      await settled();
      expect(pushesTo(patient.user_id)).toHaveLength(1);

      await request(app.getHttpServer()) // cancel, then bring it back: a fresh posted_at
        .post(`/v1/individual/requirements/${jobId}/cancel`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(200);
      await request(app.getHttpServer())
        .post(`/v1/individual/requirements/${jobId}/reactivate`)
        .set('Authorization', `Bearer ${patient.access_token}`)
        .expect(200);
      fcm.sendToUser.mockClear();
      await sweeper.sweep(inWindow()); // reposted just now: not yet
      await settled();
      expect(pushesTo(patient.user_id)).toHaveLength(0);
      await ageJob(jobId, 4);
      await sweeper.sweep(inWindow());
      await settled();
      expect(pushesTo(patient.user_id)).toHaveLength(1);
    });
  });

  describe('organisation requirements', () => {
    async function liveRequirement(suffix: string) {
      const orgRes = await request(app.getHttpServer())
        .post('/v1/auth/register/organisation')
        .send({
          phone: phone(suffix),
          code: '1234',
          organisation_name: 'Notify Hospital',
          contact_person_name: 'Notify Contact',
          organisation_type: 'hospital',
          city: 'bangalore',
          area: 'Indiranagar',
          terms_accepted: true,
        })
        .expect(201);
      const org = orgRes.body.data as { user_id: string; access_token: string };
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ type_of_nurse: 'registered_nurse', accommodation_provided: true, food_provided: false })
        .expect(201);
      const id = created.body.data.id as string;
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({})
        .expect(200);
      return { org, id };
    }

    it('tells the organisation about the approval, an applicant, and a caregiver closing out', async () => {
      fcm.sendToUser.mockClear();
      const { org, id } = await liveRequirement('0060');
      const cg = await registerCaregiver('0061');
      await settled();
      expect(pushesTo(org.user_id).find((c) => c[1] === 'Your requirement is live')![3]).toEqual({ route: '/org-home' });

      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${id}/apply`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      await settled();
      expect(pushesTo(org.user_id).find((c) => c[1] === 'A caregiver applied')![3]).toEqual({ route: '/org-home' });

      const apps = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${id}/applications`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${id}/applications/${apps.body.data[0].id}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);
      await settled();
      expect(pushesTo(cg.user_id).find((c) => c[1] === "You've been accepted")![2]).toMatch(/ORG-JOB-\d+/);

      fcm.sendToUser.mockClear();
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${id}/complete`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({})
        .expect(200);
      await settled();
      const closed = pushesTo(org.user_id).find((c) => c[1] === 'A caregiver closed the job');
      expect(closed![2]).not.toContain('again'); // a requirement does not reopen
    });

    it('tells an applicant when admin edits the requirement, and one still waiting when the organisation stops taking applications', async () => {
      const { org, id } = await liveRequirement('0062');
      const cg = await registerCaregiver('0063');
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${id}/apply`)
        .set('Authorization', `Bearer ${cg.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      fcm.sendToUser.mockClear();

      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ number_of_vacancies: 9 })
        .expect(200);
      await settled();
      expect(pushesTo(cg.user_id).map((c) => c[1])).toEqual(['Job updated']);

      fcm.sendToUser.mockClear();
      await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${id}/cancel`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      await settled();
      expect(pushesTo(cg.user_id).map((c) => c[1])).toEqual(['Job closed']);
    });

    it('nudges an organisation whose requirement has had no applicants for 3 days', async () => {
      const { org, id } = await liveRequirement('0064');
      await db.query("UPDATE organisation_requirements SET posted_at = NOW() - interval '4 days' WHERE id = $1", [id]);
      fcm.sendToUser.mockClear();
      const sweeper = app.get(NoApplicantsNudgeService);
      await sweeper.sweep(ist('2030-06-05T11:00:00'));
      await sweeper.sweep(ist('2030-06-05T11:30:00'));
      await settled();
      const nudges = pushesTo(org.user_id).filter((c) => c[1] === 'No applicants yet');
      expect(nudges).toHaveLength(1);
      expect(nudges[0][3]).toEqual({ route: '/org-home' });
    });
  });
});
