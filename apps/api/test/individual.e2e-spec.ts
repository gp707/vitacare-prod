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
 * Runs against the real Supabase Postgres. Uses the +91700003xxxx test
 * phone range (distinct from every other e2e suite — auth 0000, caregiver
 * 0001, jobs 0002). Individual accounts and caregivers created by this
 * suite are cleaned up by phone prefix; jobs/care_receivers by a
 * description-prefix marker set on every requirement's care_receiver
 * indirectly via the individual's own postings (all posted_by these test
 * users, deleted alongside them).
 */
describe('Individual (NurseNow) (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let fcmService: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };

  const testPhone = (suffix: string) => `+91700003${suffix}`;
  // Caregivers created by this suite share the same +91700003 prefix (so
  // one cleanup() covers everyone) but a disjoint suffix range (01xx) from
  // the individual accounts (00xx) to avoid phone collisions.
  const caregiverPhone = (suffix: string) => `+91700003${suffix}`;

  async function cleanup() {
    await db.query(
      `DELETE FROM job_applications WHERE job_id IN (
         SELECT id FROM jobs WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700003%')
       )`,
    );
    const orphanedCareReceivers = await db.query(
      `SELECT care_receiver_id FROM jobs WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700003%')`,
    );
    await db.query(
      `DELETE FROM jobs WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700003%')`,
    );
    if (orphanedCareReceivers.rows.length > 0) {
      await db.query(`DELETE FROM care_receivers WHERE id = ANY($1)`, [
        orphanedCareReceivers.rows.map((r) => r.care_receiver_id),
      ]);
    }
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')`,
    );
    await db.query("DELETE FROM individual_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')");
    await db.query("DELETE FROM users WHERE phone LIKE '+91700003%'");
  }

  async function registerIndividual(phoneSuffix: string, fullName = 'Test Patient') {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/individual')
      .send({ phone: testPhone(phoneSuffix), full_name: fullName, code: '1234' })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  async function registerCaregiver(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: caregiverPhone(phoneSuffix),
        full_name: 'Individual Test Caregiver',
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

  const requirementPayload = (overrides: Record<string, unknown> = {}) => ({
    care_receiver: {
      age: 74,
      gender: 'female',
      weight_kg: 58,
    },
    city: 'bangalore',
    area: 'Indiranagar',
    duty_type: 'live_in',
    start_date: '2026-09-01',
    languages: ['hindi'],
    ...overrides,
  });

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

    fcmService = { sendToUser: jest.fn(), sendToAllCaregivers: jest.fn() };
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
      .overrideProvider(FcmService)
      .useValue(fcmService)
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
       VALUES ($1, $2, $3, 'Individual E2E Super Admin', 'super_admin', true)`,
      ['individual-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'individual-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('POST /v1/auth/register/individual + login', () => {
    it('registers, returns a token, and no verification_status', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register/individual')
        .send({ phone: testPhone('0001'), full_name: 'Asha Patel', code: '1234' })
        .expect(201);
      expect(res.body.data.access_token).toBeDefined();
      expect(res.body.data.verification_status).toBeUndefined();
    });

    it('rejects a duplicate phone (AUTH_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register/individual')
        .send({ phone: testPhone('0001'), full_name: 'Someone Else', code: '5678' })
        .expect(409);
      expect(res.body.error.code).toBe('AUTH_001');
    });

    it('logs back in with phone + code', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '1234', app: 'nursenow' })
        .expect(200);
      expect(res.body.data.access_token).toBeDefined();
    });
  });

  describe('GET /v1/individual/me', () => {
    it("returns the caller's own identity, not a caregiver-style verification_status", async () => {
      const individual = await registerIndividual('0020', 'Ravi Kumar');
      const res = await request(app.getHttpServer())
        .get('/v1/individual/me')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      expect(res.body.data.full_name).toBe('Ravi Kumar');
      expect(res.body.data.is_job_posting_blocked).toBe(false);
      expect(res.body.data.verification_status).toBeUndefined();
      // Human-friendly sequential id (migration 046), starts at 500 —
      // displayed client-side as "PAT-<n>".
      expect(res.body.data.patient_number).toBeGreaterThanOrEqual(500);
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0120');
      await request(app.getHttpServer())
        .get('/v1/individual/me')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(403);
    });
  });

  describe('POST /v1/individual/requirements', () => {
    it('creates a pending_review job with no frequency_of_care/salary_amount visible yet', async () => {
      const individual = await registerIndividual('0002');
      const res = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      expect(res.body.data.status).toBe('pending_review');
      expect(res.body.data.frequency_of_care).toBeNull();
      expect(res.body.data.salary_amount).toBeNull();
      // patient_job_number backs the "PAT-JOB-<n>" display id (migration
      // 047, starts at 500) — never admin_job_number for an individual
      // posting.
      expect(res.body.data.patient_job_number).toBeGreaterThanOrEqual(500);
      expect(res.body.data.admin_job_number).toBeNull();

      const mine = await request(app.getHttpServer())
        .get('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      expect(mine.body.data).toHaveLength(1);
      expect(mine.body.data[0].status).toBe('pending_review');
      expect(mine.body.data[0].care_receiver).toMatchObject({ age: 74, gender: 'female', weight_kg: 58 });
    });

    it('rejects a second posting while the first is still pending_review (JOB_009)', async () => {
      const individual = await registerIndividual('0003');
      await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);

      const res = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(400);
      expect(res.body.error.code).toBe('JOB_009');
    });

    it('rejects a caregiver token (AUTH_007) — individual routes are individual-only', async () => {
      const caregiver = await registerCaregiver('0104');
      await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send(requirementPayload())
        .expect(403);
    });
  });

  describe('Admin approval / rejection of a pending_review requirement', () => {
    it('approving via PATCH /v1/admin/jobs/:id sets frequency_of_care/salary_amount, activates it, and it becomes visible to the individual', async () => {
      const individual = await registerIndividual('0005');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;

      const approved = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'monthly', salary_amount: 28000 }))
        .expect(200);
      expect(approved.body.data.status).toBe('active');
      expect(approved.body.data.frequency_of_care).toBe('monthly');
      expect(approved.body.data.salary_amount).toBe(28000);

      const mine = await request(app.getHttpServer())
        .get('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      expect(mine.body.data[0].status).toBe('active');
      expect(mine.body.data[0].frequency_of_care).toBe('monthly');
      expect(mine.body.data[0].salary_amount).toBe(28000);
    });

    it('an approved (active) requirement shows up on GET /v1/caregiver/jobs, and a caregiver can apply', async () => {
      const individual = await registerIndividual('0006');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'daily', salary_amount: 1800 }))
        .expect(200);

      const caregiver = await registerCaregiver('0107');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);

      const jobsList = await request(app.getHttpServer())
        .get('/v1/caregiver/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      expect(jobsList.body.data.map((j: { id: string }) => j.id)).toContain(jobId);

      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const applicants = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      expect(applicants.body.data).toHaveLength(1);
      expect(applicants.body.data[0].profile_id).toBe(caregiver.profile_id);
    });

    it('the individual can accept an applicant themselves, closing the job and assigning the caregiver', async () => {
      const individual = await registerIndividual('0008');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'daily', salary_amount: 1800 }))
        .expect(200);

      const caregiver = await registerCaregiver('0109');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const applyRes = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      const applicants = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      const applicationId = applicants.body.data[0].id;

      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);

      const caregiverProfile = await db.query(
        'SELECT verification_status FROM caregiver_profiles WHERE user_id = $1',
        [caregiver.user_id],
      );
      expect(caregiverProfile.rows[0].verification_status).toBe('assigned');

      const jobRow = await db.query('SELECT status FROM jobs WHERE id = $1', [jobId]);
      expect(jobRow.rows[0].status).toBe('closed');
      void applyRes;
    });

    it("lets the individual view an applicant's full profile, ownership-checked, without leaking Aadhaar/qualification-document URLs", async () => {
      const individual = await registerIndividual('0028');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'daily', salary_amount: 1800 }))
        .expect(200);

      const caregiver = await registerCaregiver('0130');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      const applicants = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      const applicationId = applicants.body.data[0].id;

      const profile = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications/${applicationId}/profile`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      expect(profile.body.data.profile_id).toBe(caregiver.profile_id);
      expect(profile.body.data.full_name).toBeDefined();
      expect(profile.body.data.email).toBeUndefined();
      expect(profile.body.data.aadhaar_document_url).toBeUndefined();
      expect(profile.body.data.qualification_document_url).toBeUndefined();
      expect(profile.body.data.other_document_urls).toBeUndefined();

      // Ownership check: another individual can't view this applicant via a job they don't own.
      const outsider = await registerIndividual('0029');
      const outsiderJob = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${outsider.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const forbidden = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${outsiderJob.body.data.id}/applications/${applicationId}/profile`)
        .set('Authorization', `Bearer ${outsider.access_token}`)
        .expect(404);
      expect(forbidden.body.error.code).toBe('GEN_002');
    });

    it('requires a reason to reject an applicant (JOB_012), and stores it once given', async () => {
      const individual = await registerIndividual('0027');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'daily', salary_amount: 1800 }))
        .expect(200);

      const caregiver = await registerCaregiver('0122');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      const applicants = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      const applicationId = applicants.body.data[0].id;

      const noReason = await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ status: 'rejected' })
        .expect(400);
      expect(noReason.body.error.code).toBe('JOB_012');

      const blankReason = await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ status: 'rejected', reason: '   ' })
        .expect(400);
      expect(blankReason.body.error.code).toBe('JOB_012');

      await request(app.getHttpServer())
        .patch(`/v1/individual/requirements/${jobId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ status: 'rejected', reason: 'Schedule does not match our needs' })
        .expect(200);

      const afterDecision = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${individual.access_token}`)
        .expect(200);
      expect(afterDecision.body.data[0].status).toBe('rejected');
      expect(afterDecision.body.data[0].decline_reason).toBe('Schedule does not match our needs');
    });

    it("rejects deciding on another individual's requirement (ownership check, GEN_002)", async () => {
      const owner = await registerIndividual('0010');
      const outsider = await registerIndividual('0011');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${owner.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;

      const res = await request(app.getHttpServer())
        .get(`/v1/individual/requirements/${jobId}/applications`)
        .set('Authorization', `Bearer ${outsider.access_token}`)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('admin retains full parity — can decide an application on an individual-posted job too', async () => {
      const individual = await registerIndividual('0012');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'daily', salary_amount: 1800 }))
        .expect(200);

      const caregiver = await registerCaregiver('0113');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.posted_by_role).toBe('individual');
      const applicationId = detail.body.data.applications[0].id;

      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'accepted' })
        .expect(200);

      const jobRow = await db.query('SELECT status FROM jobs WHERE id = $1', [jobId]);
      expect(jobRow.rows[0].status).toBe('closed');
    });

    it('admin can reject a pending_review requirement with a reason, and it never goes live', async () => {
      const individual = await registerIndividual('0014');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;

      const rejected = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}/reject`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ reason: 'Duplicate posting' })
        .expect(200);
      expect(rejected.body.data.status).toBe('closed');

      const jobRow = await db.query('SELECT status, rejection_reason FROM jobs WHERE id = $1', [jobId]);
      expect(jobRow.rows[0].status).toBe('closed');
      expect(jobRow.rows[0].rejection_reason).toBe('Duplicate posting');

      // Now free to post a new one — the rejected one no longer counts as live.
      await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
    });

    it('rejects rejecting a job that is not pending_review (JOB_011)', async () => {
      const individual = await registerIndividual('0015');
      const created = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const jobId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(requirementPayload({ frequency_of_care: 'daily', salary_amount: 1800 }))
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${jobId}/reject`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ reason: 'too late' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_011');
    });
  });

  describe('Admin blocking (GET/PATCH /v1/admin/individuals)', () => {
    it('lists individuals created by this suite', async () => {
      const individual = await registerIndividual('0016');
      const res = await request(app.getHttpServer())
        .get('/v1/admin/individuals?limit=100')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.map((i: { user_id: string }) => i.user_id)).toContain(individual.user_id);
    });

    it('job_posting_blocked rejects a new posting (JOB_010) but does not log the individual out', async () => {
      const individual = await registerIndividual('0017');
      await request(app.getHttpServer())
        .patch(`/v1/admin/individuals/${individual.user_id}/block`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'job_posting', reason: 'Suspicious activity' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(403);
      expect(res.body.error.code).toBe('JOB_010');

      // Still logs in fine — only posting is blocked.
      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0017'), code: '1234', app: 'nursenow' })
        .expect(200);

      await request(app.getHttpServer())
        .patch(`/v1/admin/individuals/${individual.user_id}/unblock`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'job_posting' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/v1/individual/requirements')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send(requirementPayload())
        .expect(201);
    });

    it('a full block (level=full) rejects login entirely (AUTH_004), with the reason visible via admin detail', async () => {
      const individual = await registerIndividual('0018');
      await request(app.getHttpServer())
        .patch(`/v1/admin/individuals/${individual.user_id}/block`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'full', reason: 'Fraudulent postings' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0018'), code: '1234', app: 'nursenow' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_004');

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/individuals/${individual.user_id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.is_active).toBe(false);
      expect(detail.body.data.block_reason).toBe('Fraudulent postings');

      await request(app.getHttpServer())
        .patch(`/v1/admin/individuals/${individual.user_id}/unblock`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'full' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0018'), code: '1234', app: 'nursenow' })
        .expect(200);
    });

    it('rejects a caregiver token (AUTH_007) — admin/individuals routes are admin-only', async () => {
      const caregiver = await registerCaregiver('0119');
      await request(app.getHttpServer())
        .get('/v1/admin/individuals')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(403);
    });
  });

  describe('PATCH /v1/individual/profile/phone + /profile/code', () => {
    it('changes the phone number and the individual can log in with it', async () => {
      const individual = await registerIndividual('0021');
      await request(app.getHttpServer())
        .patch('/v1/individual/profile/phone')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ phone: testPhone('0022') })
        .expect(200);

      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0022'), code: '1234', app: 'nursenow' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0021'), code: '1234', app: 'nursenow' })
        .expect(404);
    });

    it('rejects a phone already registered to another account (AUTH_001)', async () => {
      const individual = await registerIndividual('0023');
      await registerIndividual('0024');
      const res = await request(app.getHttpServer())
        .patch('/v1/individual/profile/phone')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ phone: testPhone('0024') })
        .expect(409);
      expect(res.body.error.code).toBe('AUTH_001');
    });

    it('changes the login code and the individual can log in with the new one only', async () => {
      const individual = await registerIndividual('0025');
      await request(app.getHttpServer())
        .patch('/v1/individual/profile/code')
        .set('Authorization', `Bearer ${individual.access_token}`)
        .send({ code: '4321' })
        .expect(200);

      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0025'), code: '4321', app: 'nursenow' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0025'), code: '1234', app: 'nursenow' })
        .expect(401);
    });

    it('rejects a caregiver token (AUTH_007) on both endpoints', async () => {
      const caregiver = await registerCaregiver('0121');
      await request(app.getHttpServer())
        .patch('/v1/individual/profile/phone')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ phone: testPhone('0026') })
        .expect(403);
      await request(app.getHttpServer())
        .patch('/v1/individual/profile/code')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ code: '4321' })
        .expect(403);
    });
  });
});
