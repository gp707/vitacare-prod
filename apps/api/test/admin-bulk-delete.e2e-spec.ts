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
 * Runs against the real Supabase Postgres. Uses the +91700013xxxx test
 * phone range (distinct from every other e2e suite). Verifies the
 * permanent hard-delete behavior directly against the DB (rows genuinely
 * gone, not just status-changed) — this is the one suite in the codebase
 * that's actually testing destructive deletion, so every test creates its
 * own fully-disposable rows and asserts on raw row counts afterward.
 */
describe('Admin Bulk Delete (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let superAdminId: string;
  let regularAdminToken: string;
  let caregiverToken: string;
  let fcmService: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };

  const testPhone = (suffix: string) => `+91700013${suffix}`;
  const jobDescriptionPrefix = 'BULK_DELETE_E2E_TEST:';

  async function cleanup() {
    await db.query(
      `DELETE FROM job_applications WHERE job_id IN (SELECT id FROM jobs WHERE description LIKE $1)`,
      [`${jobDescriptionPrefix}%`],
    );
    const orphanedCareReceivers = await db.query(`SELECT care_receiver_id FROM jobs WHERE description LIKE $1`, [
      `${jobDescriptionPrefix}%`,
    ]);
    await db.query(`DELETE FROM jobs WHERE description LIKE $1`, [`${jobDescriptionPrefix}%`]);
    if (orphanedCareReceivers.rows.length > 0) {
      await db.query(`DELETE FROM care_receivers WHERE id = ANY($1)`, [
        orphanedCareReceivers.rows.map((r) => r.care_receiver_id),
      ]);
    }
    await db.query(
      `DELETE FROM organisation_requirement_applications WHERE requirement_id IN (
         SELECT id FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700013%')
       )`,
    );
    await db.query(
      `DELETE FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700013%')`,
    );
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700013%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700013%')`,
    );
    await db.query(
      "DELETE FROM organisation_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700013%')",
    );
    await db.query(
      "DELETE FROM caregiver_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700013%')",
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700013%'");
  }

  async function registerCaregiver(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: testPhone(phoneSuffix),
        full_name: 'Bulk Delete Test Subject',
        gender: 'female',
        age: 28,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      });
    return res.body.data as { user_id: string; profile_id: string; access_token: string };
  }

  const defaultCareReceiver = {
    age: 72,
    gender: 'female',
    weight_kg: 58,
    feeding_type: 'oral_feeding',
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
        salary_amount: '30000',
        preferred_gender: 'female',
        care_duration: 'few_weeks',
        ...jobOverrides,
      })
      .expect(201);
    return res.body.data as { id: string; care_receiver_id: string };
  }

  async function registerOrganisation(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/organisation')
      .send({
        phone: testPhone(phoneSuffix),
        code: '1234',
        organisation_name: 'Bulk Delete Test Hospital',
        contact_person_name: 'Test Contact',
        organisation_type: 'hospital',
        city: 'bangalore',
        area: 'Indiranagar',
        terms_accepted: true,
      })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  async function createRequirement(orgToken: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/organisation/requirements')
      .set('Authorization', `Bearer ${orgToken}`)
      .send({
        type_of_nurse: 'registered_nurse',
        accommodation_provided: true,
        food_provided: true,
        duration_type: 'short_term',
      })
      .expect(201);
    const requirementId = res.body.data.id as string;
    await request(app.getHttpServer())
      .patch(`/v1/admin/organisation-requirements/${requirementId}`)
      .set('Authorization', `Bearer ${superAdminToken}`)
      .expect(200);
    return requirementId;
  }

  async function makeAvailable(userId: string) {
    await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [userId]);
  }

  beforeAll(async () => {
    db = new Client({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false },
    });
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
       VALUES ($1, $2, $3, 'Bulk Delete E2E Super Admin', 'super_admin', true)`,
      ['bulk-delete-super-admin-e2e@e2e-test.local', testPhone('0997'), passwordHash],
    );
    await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ($1, $2, $3, 'Bulk Delete E2E Regular Admin', 'admin', true)`,
      ['bulk-delete-regular-admin-e2e@e2e-test.local', testPhone('0998'), passwordHash],
    );

    const superLogin = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'bulk-delete-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = superLogin.body.data.access_token;
    const superAdminRow = await db.query('SELECT id FROM users WHERE email = $1', [
      'bulk-delete-super-admin-e2e@e2e-test.local',
    ]);
    superAdminId = superAdminRow.rows[0].id;

    const regularLogin = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'bulk-delete-regular-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    regularAdminToken = regularLogin.body.data.access_token;

    const caregiver = await registerCaregiver('0001');
    caregiverToken = caregiver.access_token;
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('POST /v1/admin/jobs/bulk-delete', () => {
    it('rejects a regular admin token — super_admin only (AUTH_007)', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${regularAdminToken}`)
        .send({ items: [{ id: job.id, type: 'job' }], confirm: 'DELETE' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${caregiverToken}`)
        .send({ items: [{ id: job.id, type: 'job' }], confirm: 'DELETE' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('rejects a request missing the literal confirm: "DELETE" (GEN_001)', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ items: [{ id: job.id, type: 'job' }], confirm: 'yes please' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an empty items array (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ items: [], confirm: 'DELETE' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an invalid item type (GEN_001)', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ items: [{ id: job.id, type: 'not_a_real_type' }], confirm: 'DELETE' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it(
      'permanently deletes a job — the job, its care_receiver, and its applications are all genuinely ' +
        'gone from the database, as if the caregiver never applied',
      async () => {
        const caregiver = await registerCaregiver('0002');
        await makeAvailable(caregiver.user_id);
        const job = await createJob();
        await request(app.getHttpServer())
          .post(`/v1/caregiver/jobs/${job.id}/apply`)
          .set('Authorization', `Bearer ${caregiver.access_token}`)
          .send({ status: 'applied' })
          .expect(200);

        const beforeApps = await db.query('SELECT id FROM job_applications WHERE job_id = $1', [job.id]);
        expect(beforeApps.rows.length).toBe(1);

        const res = await request(app.getHttpServer())
          .post('/v1/admin/jobs/bulk-delete')
          .set('Authorization', `Bearer ${superAdminToken}`)
          .send({ items: [{ id: job.id, type: 'job' }], confirm: 'DELETE' })
          .expect(200);

        expect(res.body.data).toEqual({ jobs_deleted: 1, requirements_deleted: 0, applications_deleted: 1 });

        const jobRow = await db.query('SELECT id FROM jobs WHERE id = $1', [job.id]);
        expect(jobRow.rows).toHaveLength(0);
        const careReceiverRow = await db.query('SELECT id FROM care_receivers WHERE id = $1', [
          job.care_receiver_id,
        ]);
        expect(careReceiverRow.rows).toHaveLength(0);
        const appRows = await db.query('SELECT id FROM job_applications WHERE job_id = $1', [job.id]);
        expect(appRows.rows).toHaveLength(0);
      },
    );

    it(
      'permanently deletes an organisation requirement — the requirement and its applications are ' +
        'genuinely gone from the database',
      async () => {
        const org = await registerOrganisation('0100');
        const caregiver = await registerCaregiver('0003');
        await makeAvailable(caregiver.user_id);
        const requirementId = await createRequirement(org.access_token);
        await request(app.getHttpServer())
          .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
          .set('Authorization', `Bearer ${caregiver.access_token}`)
          .send({ status: 'applied' })
          .expect(200);

        const res = await request(app.getHttpServer())
          .post('/v1/admin/jobs/bulk-delete')
          .set('Authorization', `Bearer ${superAdminToken}`)
          .send({ items: [{ id: requirementId, type: 'organisation_requirement' }], confirm: 'DELETE' })
          .expect(200);

        expect(res.body.data).toEqual({ jobs_deleted: 0, requirements_deleted: 1, applications_deleted: 1 });

        const requirementRow = await db.query('SELECT id FROM organisation_requirements WHERE id = $1', [
          requirementId,
        ]);
        expect(requirementRow.rows).toHaveLength(0);
        const appRows = await db.query(
          'SELECT id FROM organisation_requirement_applications WHERE requirement_id = $1',
          [requirementId],
        );
        expect(appRows.rows).toHaveLength(0);
      },
    );

    it('deletes a mix of jobs and organisation requirements in one call, atomically, and audit-logs one entry', async () => {
      const org = await registerOrganisation('0101');
      const jobA = await createJob();
      const jobB = await createJob();
      const requirementId = await createRequirement(org.access_token);

      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          items: [
            { id: jobA.id, type: 'job' },
            { id: jobB.id, type: 'job' },
            { id: requirementId, type: 'organisation_requirement' },
          ],
          confirm: 'DELETE',
        })
        .expect(200);

      expect(res.body.data).toEqual({ jobs_deleted: 2, requirements_deleted: 1, applications_deleted: 0 });

      const remainingJobs = await db.query('SELECT id FROM jobs WHERE id = ANY($1)', [[jobA.id, jobB.id]]);
      expect(remainingJobs.rows).toHaveLength(0);
      const remainingRequirement = await db.query('SELECT id FROM organisation_requirements WHERE id = $1', [
        requirementId,
      ]);
      expect(remainingRequirement.rows).toHaveLength(0);

      const audit = await db.query(
        `SELECT action, before_value FROM audit_logs WHERE action = 'jobs_bulk_deleted' AND user_id = $1
         ORDER BY created_at DESC LIMIT 1`,
        [superAdminId],
      );
      expect(audit.rows).toHaveLength(1);
      expect(audit.rows[0].before_value.jobs_deleted).toBe(2);
      expect(audit.rows[0].before_value.requirements_deleted).toBe(1);
    });

    it('silently ignores an id that no longer exists (already deleted) rather than erroring', async () => {
      const job = await createJob();
      await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ items: [{ id: job.id, type: 'job' }], confirm: 'DELETE' })
        .expect(200);

      // Deleting the same (now-nonexistent) id again succeeds with a 0 count,
      // not a 404/500 — bulk operations must be safely re-triggerable.
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/bulk-delete')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ items: [{ id: job.id, type: 'job' }], confirm: 'DELETE' })
        .expect(200);
      expect(res.body.data).toEqual({ jobs_deleted: 0, requirements_deleted: 0, applications_deleted: 0 });
    });
  });
});
