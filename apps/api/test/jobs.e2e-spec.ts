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
 * Runs against the real Supabase Postgres. Uses the +91700002xxxx test
 * phone range (distinct from every other e2e suite). Jobs created by this
 * suite are cleaned up by admin_id/description prefix since jobs aren't
 * tied to a phone number.
 */
describe('Jobs (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let fcmService: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };

  const testPhone = (suffix: string) => `+91700002${suffix}`;
  const jobDescriptionPrefix = 'JOBS_E2E_TEST:';

  async function cleanup() {
    await db.query(
      `DELETE FROM job_responses WHERE job_id IN (SELECT id FROM jobs WHERE description LIKE $1)`,
      [`${jobDescriptionPrefix}%`],
    );
    await db.query(`DELETE FROM jobs WHERE description LIKE $1`, [`${jobDescriptionPrefix}%`]);
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700002%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700002%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700002%' AND role = 'caregiver'");
    await db.query("DELETE FROM users WHERE phone LIKE '+91700002%'");
  }

  async function registerCaregiver(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: testPhone(phoneSuffix),
        full_name: 'Jobs Test Subject',
        gender: 'female',
        age: 28,
        languages: ['hindi'],
        code: '1234',
      });
    return res.body.data as { user_id: string; profile_id: string; access_token: string };
  }

  async function createJob(overrides: Record<string, unknown> = {}) {
    const res = await request(app.getHttpServer())
      .post('/v1/admin/jobs')
      .set('Authorization', `Bearer ${superAdminToken}`)
      .send({
        work_type: 'bedside_care',
        city: 'bangalore',
        description: `${jobDescriptionPrefix} Need a bedside caregiver`,
        duty_timings: '24hrs_live_in',
        language: 'hindi',
        gender_needed: 'female',
        religion: 'hindu',
        ...overrides,
      })
      .expect(201);
    return res.body.data as { id: string; status: string };
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
       VALUES ($1, $2, $3, 'Jobs E2E Super Admin', 'super_admin', true)`,
      ['jobs-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );

    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'jobs-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('POST /v1/admin/jobs', () => {
    it('creates a job, broadcasts a push to all caregivers, and audit-logs it', async () => {
      fcmService.sendToAllCaregivers.mockClear();
      const job = await createJob();
      expect(job.status).toBe('active');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'New Job: Bedside Care - ₹28,000–₹35,000',
        'Bangalore | 24Hrs (Live-In) | IMMEDIATELY APPLY',
      );

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE entity_type = 'jobs' AND entity_id = $1`,
        [job.id],
      );
      expect(audit.rows.map((r) => r.action)).toContain('job_posted');
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0001');
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({
          work_type: 'bedside_care',
          city: 'bangalore',
          description: 'x',
          duty_timings: '24hrs_live_in',
          language: 'hindi',
          gender_needed: 'female',
          religion: 'hindu',
        })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('rejects gender_needed = other (GEN_001, jobs table only allows male/female)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          work_type: 'bedside_care',
          city: 'bangalore',
          description: `${jobDescriptionPrefix} invalid gender test`,
          duty_timings: '24hrs_live_in',
          language: 'hindi',
          gender_needed: 'other',
          religion: 'hindu',
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });
  });

  describe('GET /v1/admin/jobs and /v1/admin/jobs/:id', () => {
    it('lists jobs with pagination meta', async () => {
      await createJob();
      const res = await request(app.getHttpServer())
        .get('/v1/admin/jobs?limit=5')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.meta).toEqual(
        expect.objectContaining({ page: 1, limit: 5 }),
      );
      expect(res.body.data.length).toBeGreaterThan(0);
    });

    it('returns job detail with an empty responses array before anyone responds', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.id).toBe(job.id);
      expect(res.body.data.responses).toEqual([]);
    });

    it('returns GEN_002 for a non-existent job', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/jobs/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });
  });

  describe('PATCH /v1/admin/jobs/:id/close', () => {
    it('closes an active job', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/close`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Job closed', status: 'closed' });

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.status).toBe('closed');
    });
  });

  describe('POST /v1/admin/jobs/:id/remind', () => {
    it('broadcasts a reminder push and audit-logs it', async () => {
      const job = await createJob();
      fcmService.sendToAllCaregivers.mockClear();

      const res = await request(app.getHttpServer())
        .post(`/v1/admin/jobs/${job.id}/remind`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Reminder sent' });
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'Reminder: Bedside Care - ₹28,000–₹35,000',
        "Bangalore | 24Hrs (Live-In) | APPLY NOW BEFORE IT'S FILLED",
      );

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE entity_type = 'jobs' AND entity_id = $1`,
        [job.id],
      );
      expect(audit.rows.map((r) => r.action)).toContain('job_reminder_sent');
    });

    it('rejects a reminder for a closed job (JOB_005)', async () => {
      const job = await createJob();
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/close`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      fcmService.sendToAllCaregivers.mockClear();
      const res = await request(app.getHttpServer())
        .post(`/v1/admin/jobs/${job.id}/remind`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('JOB_005');
      expect(fcmService.sendToAllCaregivers).not.toHaveBeenCalled();
    });

    it('returns GEN_002 for a non-existent job', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs/00000000-0000-0000-0000-000000000000/remind')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0009');
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/admin/jobs/${job.id}/remind`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });

  describe('GET /v1/caregiver/jobs', () => {
    it('lists only active jobs, viewable regardless of verification status', async () => {
      const caregiver = await registerCaregiver('0002'); // fresh, still pending_call
      const activeJob = await createJob();
      const closedJob = await createJob();
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${closedJob.id}/close`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .get('/v1/caregiver/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      const ids = res.body.data.map((j: { id: string }) => j.id);
      expect(ids).toContain(activeJob.id);
      expect(ids).not.toContain(closedJob.id);
      expect(res.body.data.find((j: { id: string }) => j.id === activeJob.id).my_response).toBeNull();
    });
  });

  describe('POST /v1/caregiver/jobs/:id/respond', () => {
    it('rejects a non-available/assigned caregiver (JOB_001)', async () => {
      const caregiver = await registerCaregiver('0003'); // pending_call
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'accepted' })
        .expect(403);
      expect(res.body.error.code).toBe('JOB_001');
    });

    it('rejects an invalid response value (JOB_004)', async () => {
      const caregiver = await registerCaregiver('0004');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'maybe' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_004');
    });

    it('rejects more_details without a message (JOB_003)', async () => {
      const caregiver = await registerCaregiver('0005');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'more_details' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_003');
    });

    it('rejects responding to a closed job (JOB_002)', async () => {
      const caregiver = await registerCaregiver('0006');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/close`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'accepted' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_002');
    });

    it('records the response, updates in place on re-respond, and shows up in admin job detail', async () => {
      const caregiver = await registerCaregiver('0007');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();

      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'more_details', message: 'What are the exact duty hours?' })
        .expect(200);

      const myJobs = await request(app.getHttpServer())
        .get('/v1/caregiver/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      expect(myJobs.body.data.find((j: { id: string }) => j.id === job.id).my_response).toBe(
        'more_details',
      );

      // Re-responding updates the same row rather than creating a duplicate.
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'accepted' })
        .expect(200);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.responses).toHaveLength(1);
      expect(detail.body.data.responses[0]).toEqual(
        expect.objectContaining({ response: 'accepted', full_name: 'Jobs Test Subject' }),
      );
    });

    it('allows an assigned caregiver to respond too', async () => {
      const caregiver = await registerCaregiver('0008');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'assigned' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ response: 'rejected' })
        .expect(200);
    });

    it('rejects a plain admin token (AUTH_007) — caregiver-jobs routes are caregiver-only', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/respond`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ response: 'accepted' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });
});
