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
 * Runs against the real Supabase Postgres. Uses the +91700005xxxx test
 * phone range (distinct from every other e2e suite). Phase 1 (caregiver
 * reports) + Phase 2 (patient/individual reports). Organisation reports are
 * added in a later phase.
 */
describe('Admin Reports (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let fcmService: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };

  const testPhone = (suffix: string) => `+91700005${suffix}`;
  const jobDescriptionPrefix = 'ADMIN_REPORTS_E2E_TEST:';
  const orgName = 'Admin Reports E2E Hospital';

  async function cleanup() {
    await db.query(
      `DELETE FROM organisation_requirement_applications WHERE requirement_id IN (
         SELECT id FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700005%')
       )`,
    );
    await db.query(
      `DELETE FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700005%')`,
    );
    await db.query(
      `DELETE FROM job_applications WHERE job_id IN (SELECT id FROM jobs WHERE description LIKE $1)`,
      [`${jobDescriptionPrefix}%`],
    );
    const orphanedCareReceivers = await db.query(
      `SELECT care_receiver_id FROM jobs WHERE description LIKE $1`,
      [`${jobDescriptionPrefix}%`],
    );
    await db.query(`DELETE FROM jobs WHERE description LIKE $1`, [`${jobDescriptionPrefix}%`]);
    if (orphanedCareReceivers.rows.length > 0) {
      await db.query(`DELETE FROM care_receivers WHERE id = ANY($1)`, [
        orphanedCareReceivers.rows.map((r) => r.care_receiver_id),
      ]);
    }
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700005%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700005%')`,
    );
    await db.query(
      "DELETE FROM organisation_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700005%')",
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700005%' AND role = 'caregiver'");
    await db.query("DELETE FROM users WHERE phone LIKE '+91700005%'");
  }

  async function registerCaregiver(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: testPhone(phoneSuffix),
        full_name: 'Reports Test Subject',
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

  async function markAvailable(userId: string) {
    await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
      userId,
    ]);
  }

  async function registerIndividual(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/individual')
      .send({
        phone: testPhone(phoneSuffix),
        full_name: 'Reports Test Patient',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  const individualRequirementPayload = (overrides: Record<string, unknown> = {}) => ({
    care_receiver: { age: 74, gender: 'female', weight_kg: 58 },
    city: 'bangalore',
    area: 'Indiranagar',
    description: `${jobDescriptionPrefix} individual posting`,
    duty_type: 'live_in',
    start_date: '2026-09-01',
    languages: ['hindi'],
    ...overrides,
  });

  /** Posts a pending_review requirement as the individual, then
   *  admin-approves it (frequency_of_care/salary_amount supplied only at
   *  approval, per CLAUDE.md's Individual posting flow) — leaves it
   *  `active`. Returns the job id. */
  async function createAndApproveIndividualJob(individual: { access_token: string }) {
    const created = await request(app.getHttpServer())
      .post('/v1/individual/requirements')
      .set('Authorization', `Bearer ${individual.access_token}`)
      .send(individualRequirementPayload())
      .expect(201);
    const jobId = created.body.data.id as string;
    await request(app.getHttpServer())
      .patch(`/v1/admin/jobs/${jobId}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .send(individualRequirementPayload({ frequency_of_care: 'monthly', salary_amount: 28000 }))
      .expect(200);
    return jobId;
  }

  /** Caregiver applies (status 'applied') and is left undecided — no admin
   *  action taken. */
  async function applyCaregiverToJob(caregiver: { access_token: string }, jobId: string) {
    await request(app.getHttpServer())
      .post(`/v1/caregiver/jobs/${jobId}/apply`)
      .set('Authorization', `Bearer ${caregiver.access_token}`)
      .send({ status: 'applied' })
      .expect(200);
  }

  const defaultCareReceiver = {
    age: 72,
    gender: 'female',
    weight_kg: 58,
    mobility: 'walks_independently',
    communication: 'verbal',
    feeding_type: 'oral_independent',
    has_medical_condition: false,
    toilet_assistance: ['others'],
    requires_vital_monitoring: false,
  };

  async function createJob(overrides: Record<string, unknown> = {}) {
    const { care_receiver, ...jobOverrides } = overrides as { care_receiver?: Record<string, unknown> };
    const res = await request(app.getHttpServer())
      .post('/v1/admin/jobs')
      .set('Authorization', `Bearer ${superAdminToken}`)
      .send({
        care_receiver: { ...defaultCareReceiver, ...care_receiver },
        city: 'bangalore',
        area: 'Indiranagar',
        description: `${jobDescriptionPrefix} Need a caregiver`,
        duty_type: 'live_in',
        frequency_of_care: 'daily',
        start_date: '2026-09-01',
        languages: ['hindi'],
        salary_amount: 30000,
        preferred_gender: 'female',
        ...jobOverrides,
      })
      .expect(201);
    return res.body.data as { id: string };
  }

  /** Applies as the caregiver, then admin-accepts — leaves the caregiver
   *  `assigned` with one `accepted` job_applications row. Returns the
   *  application id so tests can backdate `accepted_at` directly. */
  async function acceptCaregiverOntoJob(caregiver: { access_token: string; profile_id: string }, jobId: string) {
    await request(app.getHttpServer())
      .post(`/v1/caregiver/jobs/${jobId}/apply`)
      .set('Authorization', `Bearer ${caregiver.access_token}`)
      .send({ status: 'applied' })
      .expect(200);
    const detail = await request(app.getHttpServer())
      .get(`/v1/admin/jobs/${jobId}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .expect(200);
    const application = detail.body.data.applications.find(
      (a: { profile_id: string }) => a.profile_id === caregiver.profile_id,
    );
    await request(app.getHttpServer())
      .patch(`/v1/admin/jobs/${jobId}/applications/${application.id}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .send({ status: 'accepted' })
      .expect(200);
    return application.id as string;
  }

  async function registerOrganisation(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/organisation')
      .send({
        phone: testPhone(phoneSuffix),
        code: '1234',
        organisation_name: orgName,
        contact_person_name: 'Reports Test Contact',
        organisation_type: 'hospital',
        city: 'bangalore',
        area: 'Indiranagar',
        terms_accepted: true,
      })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  /** Posts + admin-approves a requirement in one step, returning its id. */
  async function createAndApproveRequirement(org: { access_token: string }) {
    const created = await request(app.getHttpServer())
      .post('/v1/organisation/requirements')
      .set('Authorization', `Bearer ${org.access_token}`)
      .send({ type_of_nurse: 'registered_nurse', accommodation_provided: true, food_provided: false })
      .expect(201);
    const requirementId = created.body.data.id as string;
    await request(app.getHttpServer())
      .patch(`/v1/admin/organisation-requirements/${requirementId}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .send({
        type_of_nurse: 'registered_nurse',
        frequency_of_care: 'monthly',
        salary_amount: 40000,
        schedule_type: 'specific_days',
        schedule_repeat: 'monthly',
        specific_days: [3, 12, 20],
        accommodation_provided: true,
        food_provided: false,
      })
      .expect(200);
    return requirementId;
  }

  async function acceptCaregiverOntoRequirement(
    caregiver: { access_token: string; profile_id: string },
    requirementId: string,
  ) {
    await request(app.getHttpServer())
      .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
      .set('Authorization', `Bearer ${caregiver.access_token}`)
      .send({ status: 'applied' })
      .expect(200);
    const applicants = await request(app.getHttpServer())
      .get(`/v1/admin/organisation-requirements/${requirementId}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .expect(200);
    const application = applicants.body.data.applications.find(
      (a: { profile_id: string }) => a.profile_id === caregiver.profile_id,
    );
    await request(app.getHttpServer())
      .patch(`/v1/admin/organisation-requirements/${requirementId}/applications/${application.id}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .send({ status: 'accepted' })
      .expect(200);
    return application.id as string;
  }

  /** Caregiver applies (status 'applied') and is left undecided — no admin
   *  action taken. */
  async function applyCaregiverToRequirement(caregiver: { access_token: string }, requirementId: string) {
    await request(app.getHttpServer())
      .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
      .set('Authorization', `Bearer ${caregiver.access_token}`)
      .send({ status: 'applied' })
      .expect(200);
  }

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
       VALUES ($1, $2, $3, 'Reports E2E Super Admin', 'super_admin', true)`,
      ['reports-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'reports-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('GET /v1/admin/reports/caregivers/unassigned-or-no-duty', () => {
    it('includes a never-worked caregiver (pending_call) with ever_had_duty false', async () => {
      const caregiver = await registerCaregiver('0001');

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/unassigned-or-no-duty')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === caregiver.profile_id);
      expect(row).toBeDefined();
      expect(row.verification_status).toBe('pending_call');
      expect(row.ever_had_duty).toBe(false);
    });

    it('includes an available caregiver who previously completed a job, with ever_had_duty true', async () => {
      const caregiver = await registerCaregiver('0002');
      await markAvailable(caregiver.user_id);
      const job = await createJob();
      await acceptCaregiverOntoJob(caregiver, job.id);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/complete`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/unassigned-or-no-duty')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === caregiver.profile_id);
      expect(row).toBeDefined();
      expect(row.ever_had_duty).toBe(true);
    });

    it('excludes a caregiver currently assigned to a job', async () => {
      const caregiver = await registerCaregiver('0003');
      await markAvailable(caregiver.user_id);
      const job = await createJob();
      await acceptCaregiverOntoJob(caregiver, job.id);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/unassigned-or-no-duty')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      expect(res.body.data.some((r: { profile_id: string }) => r.profile_id === caregiver.profile_id)).toBe(
        false,
      );
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0004');
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/unassigned-or-no-duty')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });

  describe('GET /v1/admin/reports/caregivers/stalled-duty', () => {
    it('includes a job engagement accepted more than N days ago, excludes one within the window', async () => {
      const stale = await registerCaregiver('0005');
      await markAvailable(stale.user_id);
      const staleJob = await createJob();
      const staleApplicationId = await acceptCaregiverOntoJob(stale, staleJob.id);
      await db.query("UPDATE job_applications SET accepted_at = NOW() - INTERVAL '10 days' WHERE id = $1", [
        staleApplicationId,
      ]);

      const fresh = await registerCaregiver('0006');
      await markAvailable(fresh.user_id);
      const freshJob = await createJob();
      await acceptCaregiverOntoJob(fresh, freshJob.id);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/stalled-duty?days=5')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(stale.profile_id);
      expect(profileIds).not.toContain(fresh.profile_id);
      const staleRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === stale.profile_id);
      expect(staleRow.engagement_type).toBe('job');
      expect(staleRow.days_since_accepted).toBeGreaterThanOrEqual(10);
    }, 30000);

    it('a higher day threshold excludes an engagement that was included at a lower one', async () => {
      const caregiver = await registerCaregiver('0007');
      await markAvailable(caregiver.user_id);
      const job = await createJob();
      const applicationId = await acceptCaregiverOntoJob(caregiver, job.id);
      await db.query("UPDATE job_applications SET accepted_at = NOW() - INTERVAL '10 days' WHERE id = $1", [
        applicationId,
      ]);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/stalled-duty?days=20')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      expect(res.body.data.some((r: { profile_id: string }) => r.profile_id === caregiver.profile_id)).toBe(
        false,
      );
    });

    it('also surfaces a stalled organisation-requirement engagement (engagement_type requirement)', async () => {
      const org = await registerOrganisation('0100');
      const caregiver = await registerCaregiver('0008');
      await markAvailable(caregiver.user_id);
      const requirementId = await createAndApproveRequirement(org);
      const applicationId = await acceptCaregiverOntoRequirement(caregiver, requirementId);
      await db.query(
        "UPDATE organisation_requirement_applications SET accepted_at = NOW() - INTERVAL '10 days' WHERE id = $1",
        [applicationId],
      );

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/stalled-duty?days=5')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === caregiver.profile_id);
      expect(row).toBeDefined();
      expect(row.engagement_type).toBe('requirement');
    }, 30000);

    it('rejects an invalid days value (GEN_005)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/stalled-duty?days=not-a-number')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_005');
    });
  });

  describe('GET /v1/admin/reports/caregivers/over-threshold-active', () => {
    it('includes a caregiver with more accepted engagements than the threshold, excludes one at/below it', async () => {
      const busy = await registerCaregiver('0009');
      await markAvailable(busy.user_id);
      const jobA = await createJob();
      const jobB = await createJob();
      await acceptCaregiverOntoJob(busy, jobA.id);
      await acceptCaregiverOntoJob(busy, jobB.id);

      const single = await registerCaregiver('0010');
      await markAvailable(single.user_id);
      const jobC = await createJob();
      await acceptCaregiverOntoJob(single, jobC.id);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/over-threshold-active?min_jobs=1')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(busy.profile_id);
      expect(profileIds).not.toContain(single.profile_id);
      const busyRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === busy.profile_id);
      expect(busyRow.accepted_count).toBe(2);
    }, 30000);
  });

  describe('GET /v1/admin/reports/caregivers/activity', () => {
    it('counts applications submitted within the window, sorted desc by default', async () => {
      const active = await registerCaregiver('0011');
      await markAvailable(active.user_id);
      const jobA = await createJob();
      const jobB = await createJob();
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobA.id}/apply`)
        .set('Authorization', `Bearer ${active.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobB.id}/apply`)
        .set('Authorization', `Bearer ${active.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const idle = await registerCaregiver('0012');

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/activity?days=7&order=desc')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const activeRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === active.profile_id);
      const idleRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === idle.profile_id);
      expect(activeRow.activity_count).toBe(2);
      expect(idleRow.activity_count).toBe(0);
      // desc order: active (2) ranks before idle (0).
      const activeIndex = res.body.data.findIndex((r: { profile_id: string }) => r.profile_id === active.profile_id);
      const idleIndex = res.body.data.findIndex((r: { profile_id: string }) => r.profile_id === idle.profile_id);
      expect(activeIndex).toBeLessThan(idleIndex);
    }, 30000);

    it('an application applied before the window is excluded from the count', async () => {
      const caregiver = await registerCaregiver('0013');
      await markAvailable(caregiver.user_id);
      const job = await createJob();
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      await db.query(
        `UPDATE job_applications SET applied_at = NOW() - INTERVAL '30 days'
         WHERE job_id = $1 AND profile_id = $2`,
        [job.id, caregiver.profile_id],
      );

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/activity?days=7&order=asc')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === caregiver.profile_id);
      expect(row.activity_count).toBe(0);
    });

    it('rejects a missing days value (GEN_005)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/caregivers/activity')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_005');
    });
  });

  describe('GET /v1/admin/reports/patients/no-applicants', () => {
    it('includes a live job with zero applications, excludes one with a recent applicant', async () => {
      const noApplicants = await registerIndividual('0200');
      await createAndApproveIndividualJob(noApplicants);

      const hasApplicant = await registerIndividual('0201');
      const jobId = await createAndApproveIndividualJob(hasApplicant);
      const caregiver = await registerCaregiver('0014');
      await markAvailable(caregiver.user_id);
      await applyCaregiverToJob(caregiver, jobId);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/no-applicants?days=7')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const userIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      // profile_id here is the individual_profiles id, not user_id — assert
      // via a lookup instead of comparing to user_id directly.
      const noApplicantsProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        noApplicants.user_id,
      ]);
      const hasApplicantProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        hasApplicant.user_id,
      ]);
      expect(userIds).toContain(noApplicantsProfile.rows[0].id);
      expect(userIds).not.toContain(hasApplicantProfile.rows[0].id);

      // user_id (not just profile_id) must be present — admin-web navigates
      // to /individual-detail by user_id, unlike caregivers' profile_id.
      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === noApplicantsProfile.rows[0].id);
      expect(row.user_id).toBe(noApplicants.user_id);
    }, 30000);

    it('an application older than the window still counts as "no recent applicants"', async () => {
      const individual = await registerIndividual('0202');
      const jobId = await createAndApproveIndividualJob(individual);
      const caregiver = await registerCaregiver('0015');
      await markAvailable(caregiver.user_id);
      await applyCaregiverToJob(caregiver, jobId);
      await db.query("UPDATE job_applications SET applied_at = NOW() - INTERVAL '30 days' WHERE job_id = $1", [
        jobId,
      ]);

      const profile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        individual.user_id,
      ]);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/no-applicants?days=7')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      expect(res.body.data.map((r: { profile_id: string }) => r.profile_id)).toContain(profile.rows[0].id);
    }, 30000);
  });

  describe('GET /v1/admin/reports/patients/no-pending-candidate', () => {
    it('includes a live job with zero applied candidates, excludes one with an undecided applicant', async () => {
      const noCandidate = await registerIndividual('0203');
      await createAndApproveIndividualJob(noCandidate);

      const pending = await registerIndividual('0204');
      const jobId = await createAndApproveIndividualJob(pending);
      const caregiver = await registerCaregiver('0016');
      await markAvailable(caregiver.user_id);
      await applyCaregiverToJob(caregiver, jobId);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/no-pending-candidate')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const noCandidateProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        noCandidate.user_id,
      ]);
      const pendingProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        pending.user_id,
      ]);
      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(noCandidateProfile.rows[0].id);
      expect(profileIds).not.toContain(pendingProfile.rows[0].id);
    }, 30000);

    it('excludes a job once its only applicant is accepted — accepting closes the job, so it drops out of scope entirely', async () => {
      const individual = await registerIndividual('0205');
      const jobId = await createAndApproveIndividualJob(individual);
      const caregiver = await registerCaregiver('0017');
      await markAvailable(caregiver.user_id);
      await acceptCaregiverOntoJob(caregiver, jobId);

      const profile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        individual.user_id,
      ]);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/no-pending-candidate')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      // Accepting flips the job to `closed` (CLAUDE.md), which falls
      // outside the "current live job" (active/pending_review) scope every
      // one of these reports uses — a patient who already found their
      // caregiver has nothing left to be prompted about.
      expect(res.body.data.map((r: { profile_id: string }) => r.profile_id)).not.toContain(profile.rows[0].id);
    }, 30000);
  });

  describe('GET /v1/admin/reports/patients/unconverted-applicants', () => {
    it('includes a job with an undecided applicant and zero accepted, excludes one that has an accepted applicant', async () => {
      const unconverted = await registerIndividual('0206');
      const unconvertedJobId = await createAndApproveIndividualJob(unconverted);
      const applicant = await registerCaregiver('0018');
      await markAvailable(applicant.user_id);
      await applyCaregiverToJob(applicant, unconvertedJobId);

      const converted = await registerIndividual('0207');
      const convertedJobId = await createAndApproveIndividualJob(converted);
      const acceptedCaregiver = await registerCaregiver('0019');
      await markAvailable(acceptedCaregiver.user_id);
      await acceptCaregiverOntoJob(acceptedCaregiver, convertedJobId);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/unconverted-applicants')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const unconvertedProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        unconverted.user_id,
      ]);
      const convertedProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        converted.user_id,
      ]);
      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(unconvertedProfile.rows[0].id);
      expect(profileIds).not.toContain(convertedProfile.rows[0].id);
      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === unconvertedProfile.rows[0].id);
      expect(row.applicant_count).toBe(1);
    }, 30000);

    it('excludes a job with no applicants at all', async () => {
      const individual = await registerIndividual('0208');
      await createAndApproveIndividualJob(individual);

      const profile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        individual.user_id,
      ]);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/unconverted-applicants')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      expect(res.body.data.map((r: { profile_id: string }) => r.profile_id)).not.toContain(profile.rows[0].id);
    });
  });

  describe('GET /v1/admin/reports/patients/activity', () => {
    it('counts a job posted within the window, sorted desc by default', async () => {
      const active = await registerIndividual('0209');
      await createAndApproveIndividualJob(active);
      const idle = await registerIndividual('0210');

      const activeProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        active.user_id,
      ]);
      const idleProfile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        idle.user_id,
      ]);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/activity?days=7&order=desc')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const activeRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === activeProfile.rows[0].id);
      const idleRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === idleProfile.rows[0].id);
      expect(activeRow.activity_count).toBe(1);
      expect(idleRow.activity_count).toBe(0);
      const activeIndex = res.body.data.findIndex(
        (r: { profile_id: string }) => r.profile_id === activeProfile.rows[0].id,
      );
      const idleIndex = res.body.data.findIndex((r: { profile_id: string }) => r.profile_id === idleProfile.rows[0].id);
      expect(activeIndex).toBeLessThan(idleIndex);
    }, 30000);

    it('a job posted before the window is excluded from the count', async () => {
      const individual = await registerIndividual('0211');
      const jobId = await createAndApproveIndividualJob(individual);
      await db.query("UPDATE jobs SET created_at = NOW() - INTERVAL '30 days' WHERE id = $1", [jobId]);

      const profile = await db.query('SELECT id FROM individual_profiles WHERE user_id = $1', [
        individual.user_id,
      ]);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/activity?days=7&order=asc')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === profile.rows[0].id);
      expect(row.activity_count).toBe(0);
    }, 30000);

    it('rejects a missing days value (GEN_005)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/patients/activity')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_005');
    });
  });

  describe('GET /v1/admin/reports/organisations/no-jobs-posted', () => {
    it('includes an organisation with zero requirements ever, excludes one with a requirement posted', async () => {
      const noJobs = await registerOrganisation('0101');

      const hasJobs = await registerOrganisation('0102');
      await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${hasJobs.access_token}`)
        .send({ type_of_nurse: 'registered_nurse', accommodation_provided: true, food_provided: false })
        .expect(201);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/no-jobs-posted')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const noJobsProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        noJobs.user_id,
      ]);
      const hasJobsProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        hasJobs.user_id,
      ]);
      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(noJobsProfile.rows[0].id);
      expect(profileIds).not.toContain(hasJobsProfile.rows[0].id);

      const row = res.body.data.find((r: { profile_id: string }) => r.profile_id === noJobsProfile.rows[0].id);
      expect(row.user_id).toBe(noJobs.user_id);
    });

    it('excludes an organisation whose only requirement was rejected — it still counts as "posted"', async () => {
      const org = await registerOrganisation('0103');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ type_of_nurse: 'registered_nurse', accommodation_provided: true, food_provided: false })
        .expect(201);
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${created.body.data.id}/reject`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ reason: 'Duplicate posting' })
        .expect(200);

      const profile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [org.user_id]);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/no-jobs-posted')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      expect(res.body.data.map((r: { profile_id: string }) => r.profile_id)).not.toContain(profile.rows[0].id);
    });
  });

  describe('GET /v1/admin/reports/organisations/no-applicants', () => {
    it('includes an org whose live requirement got zero applicants, excludes one with a recent applicant', async () => {
      const noApplicants = await registerOrganisation('0104');
      await createAndApproveRequirement(noApplicants);

      const hasApplicant = await registerOrganisation('0105');
      const requirementId = await createAndApproveRequirement(hasApplicant);
      const caregiver = await registerCaregiver('0020');
      await markAvailable(caregiver.user_id);
      await applyCaregiverToRequirement(caregiver, requirementId);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/no-applicants?days=7')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const noApplicantsProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        noApplicants.user_id,
      ]);
      const hasApplicantProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        hasApplicant.user_id,
      ]);
      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(noApplicantsProfile.rows[0].id);
      expect(profileIds).not.toContain(hasApplicantProfile.rows[0].id);
    }, 30000);

    it('an org with TWO live requirements is only excluded once one of them gets a recent applicant', async () => {
      const org = await registerOrganisation('0106');
      await createAndApproveRequirement(org);
      const secondRequirementId = await createAndApproveRequirement(org);
      const caregiver = await registerCaregiver('0021');
      await markAvailable(caregiver.user_id);
      await applyCaregiverToRequirement(caregiver, secondRequirementId);

      const profile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [org.user_id]);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/no-applicants?days=7')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      // One of its two requirements got an applicant — the org as a whole
      // is not "no applicants".
      expect(res.body.data.map((r: { profile_id: string }) => r.profile_id)).not.toContain(profile.rows[0].id);
    }, 30000);
  });

  describe('GET /v1/admin/reports/organisations/unconverted-applicants', () => {
    it('includes an org with an undecided applicant and zero accepted, excludes one that accepted someone', async () => {
      const unconverted = await registerOrganisation('0107');
      const unconvertedRequirementId = await createAndApproveRequirement(unconverted);
      const applicant = await registerCaregiver('0022');
      await markAvailable(applicant.user_id);
      await applyCaregiverToRequirement(applicant, unconvertedRequirementId);

      const converted = await registerOrganisation('0108');
      const convertedRequirementId = await createAndApproveRequirement(converted);
      const acceptedCaregiver = await registerCaregiver('0023');
      await markAvailable(acceptedCaregiver.user_id);
      await acceptCaregiverOntoRequirement(acceptedCaregiver, convertedRequirementId);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/unconverted-applicants')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const unconvertedProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        unconverted.user_id,
      ]);
      const convertedProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        converted.user_id,
      ]);
      const profileIds = res.body.data.map((r: { profile_id: string }) => r.profile_id);
      expect(profileIds).toContain(unconvertedProfile.rows[0].id);
      expect(profileIds).not.toContain(convertedProfile.rows[0].id);
      const row = res.body.data.find(
        (r: { profile_id: string }) => r.profile_id === unconvertedProfile.rows[0].id,
      );
      expect(row.applicant_count).toBe(1);
    }, 30000);
  });

  describe('GET /v1/admin/reports/organisations/activity', () => {
    it('counts a requirement posted within the window, sorted desc by default', async () => {
      const active = await registerOrganisation('0109');
      await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${active.access_token}`)
        .send({ type_of_nurse: 'registered_nurse', accommodation_provided: true, food_provided: false })
        .expect(201);
      const idle = await registerOrganisation('0110');

      const activeProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        active.user_id,
      ]);
      const idleProfile = await db.query('SELECT id FROM organisation_profiles WHERE user_id = $1', [
        idle.user_id,
      ]);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/activity?days=7&order=desc')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const activeRow = res.body.data.find(
        (r: { profile_id: string }) => r.profile_id === activeProfile.rows[0].id,
      );
      const idleRow = res.body.data.find((r: { profile_id: string }) => r.profile_id === idleProfile.rows[0].id);
      expect(activeRow.activity_count).toBe(1);
      expect(idleRow.activity_count).toBe(0);
      const activeIndex = res.body.data.findIndex(
        (r: { profile_id: string }) => r.profile_id === activeProfile.rows[0].id,
      );
      const idleIndex = res.body.data.findIndex(
        (r: { profile_id: string }) => r.profile_id === idleProfile.rows[0].id,
      );
      expect(activeIndex).toBeLessThan(idleIndex);
    }, 30000);

    it('rejects a missing days value (GEN_005)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/reports/organisations/activity')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_005');
    });
  });
});
