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
    mobility: 'walks_independently',
    communication: 'verbal',
    feeding_type: 'oral_independent',
    medical_assistance: [],
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
        description: `${jobDescriptionPrefix} Need a caregiver`,
        duty_type: 'live_in',
        languages: ['hindi'],
        salary_monthly: 30000,
        preferred_gender: 'female',
        ...jobOverrides,
      })
      .expect(201);
    return res.body.data as {
      id: string;
      job_number: number;
      status: string;
      care_receiver_id: string;
      salary_monthly: number;
      posted_at: string;
    };
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
    it('creates the care receiver + job, broadcasts a push to all caregivers, and audit-logs it', async () => {
      fcmService.sendToAllCaregivers.mockClear();
      const job = await createJob();
      expect(job.status).toBe('active');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'New Job: Live-In Care in Bangalore',
        'Bangalore | IMMEDIATELY APPLY',
      );

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE entity_type = 'jobs' AND entity_id = $1`,
        [job.id],
      );
      expect(audit.rows.map((r) => r.action)).toContain('job_posted');

      const careReceiver = await db.query('SELECT * FROM care_receivers WHERE id = $1', [
        job.care_receiver_id,
      ]);
      expect(careReceiver.rows[0].mobility).toBe('walks_independently');
      expect(careReceiver.rows[0].age).toBe(72);
      expect(careReceiver.rows[0].gender).toBe('female');
      expect(careReceiver.rows[0].weight_kg).toBe(58);
      expect(careReceiver.rows[0].toilet_assistance).toEqual(['others']);
      expect(careReceiver.rows[0].requires_vital_monitoring).toBe(false);
      expect(careReceiver.rows[0].vital_monitoring_types).toEqual([]);
    });

    it('assigns a sequential job_number, stores salary_monthly, and sets posted_at = created_at at creation', async () => {
      const jobA = await createJob({ salary_monthly: 28000 });
      const jobB = await createJob({ salary_monthly: 31000 });
      expect(typeof jobA.job_number).toBe('number');
      expect(jobB.job_number).toBeGreaterThan(jobA.job_number);
      expect(jobA.salary_monthly).toBe(28000);

      const row = await db.query('SELECT created_at, posted_at FROM jobs WHERE id = $1', [jobA.id]);
      expect(row.rows[0].posted_at.getTime()).toBe(row.rows[0].created_at.getTime());
    });

    it('rejects a missing/invalid salary_monthly (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: defaultCareReceiver,
          city: 'bangalore',
          description: `${jobDescriptionPrefix} salary validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 0,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an out-of-range age (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, age: 0 },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} age validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an invalid toilet_assistance value (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, toilet_assistance: ['not_a_real_value'] },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} toilet assistance validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an empty toilet_assistance array (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, toilet_assistance: [] },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} empty toilet assistance validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('accepts multiple toilet assistance options — admin can select more than one', async () => {
      const job = await createJob({
        care_receiver: { toilet_assistance: ['uses_diapers', 'uses_catheter'] },
      });
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.care_receiver.toilet_assistance).toEqual(['uses_diapers', 'uses_catheter']);
    });

    it('rejects "other_non_verbal" as a communication value — dropped, only 3 options remain (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, communication: 'other_non_verbal' },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} communication validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('requires vital_monitoring_types when requires_vital_monitoring is true (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, requires_vital_monitoring: true },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} vital monitoring validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('accepts vital monitoring types when requires_vital_monitoring is true', async () => {
      const job = await createJob({
        care_receiver: {
          requires_vital_monitoring: true,
          vital_monitoring_types: ['blood_pressure', 'oxygen_spo2'],
        },
      });
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.care_receiver.requires_vital_monitoring).toBe(true);
      expect(detail.body.data.care_receiver.vital_monitoring_types).toEqual(['blood_pressure', 'oxygen_spo2']);
    });

    it('derives start/end time from duty_type and stores languages as an array', async () => {
      const dayJob = await createJob({ duty_type: 'day_duty' });
      expect(dayJob.status).toBe('active');
      const dayRow = await db.query('SELECT start_time, end_time, languages FROM jobs WHERE id = $1', [
        dayJob.id,
      ]);
      expect(dayRow.rows[0].start_time).toBe('08:00:00');
      expect(dayRow.rows[0].end_time).toBe('20:00:00');
      expect(dayRow.rows[0].languages).toEqual(['hindi']);

      const nightJob = await createJob({ duty_type: 'night_duty' });
      const nightRow = await db.query('SELECT start_time, end_time FROM jobs WHERE id = $1', [
        nightJob.id,
      ]);
      expect(nightRow.rows[0].start_time).toBe('20:00:00');
      expect(nightRow.rows[0].end_time).toBe('08:00:00');

      const liveInRow = await db.query('SELECT start_time, end_time FROM jobs WHERE id = $1', [
        (await createJob({ duty_type: 'live_in' })).id,
      ]);
      expect(liveInRow.rows[0].start_time).toBeNull();
      expect(liveInRow.rows[0].end_time).toBeNull();
    });

    it('rejects a duty_type outside the 3 fixed shifts (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: defaultCareReceiver,
          city: 'bangalore',
          description: `${jobDescriptionPrefix} bad duty type`,
          duty_type: 'other',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an empty languages array (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: defaultCareReceiver,
          city: 'bangalore',
          description: `${jobDescriptionPrefix} empty languages`,
          duty_type: 'live_in',
          languages: [],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('accepts multiple language preferences', async () => {
      const job = await createJob({ languages: ['hindi', 'english', 'kannada'] });
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.languages).toEqual(['hindi', 'english', 'kannada']);
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0001');
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({
          care_receiver: defaultCareReceiver,
          city: 'bangalore',
          description: 'x',
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('requires tube_feeding_needs_assistance when feeding_type is tube feeding (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, feeding_type: 'tube_feeding' },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} tube feeding validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('requires medical_conditions when has_medical_condition is true (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: { ...defaultCareReceiver, has_medical_condition: true },
          city: 'bangalore',
          description: `${jobDescriptionPrefix} medical condition validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects "others" as a preferred_religion (GEN_001) — valid for a caregiver\'s own religion, not a job preference', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/jobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          care_receiver: defaultCareReceiver,
          city: 'bangalore',
          description: `${jobDescriptionPrefix} others religion validation test`,
          duty_type: 'live_in',
          languages: ['hindi'],
          salary_monthly: 30000,
          preferred_religion: 'others',
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('accepts a full care-needs payload including medical conditions', async () => {
      const job = await createJob({
        care_receiver: {
          feeding_type: 'tube_feeding',
          tube_feeding_needs_assistance: true,
          has_medical_condition: true,
          medical_conditions: ['diabetes', 'stroke'],
          medical_info: 'Needs help twice daily',
        },
      });
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.care_receiver.medical_conditions).toEqual(['diabetes', 'stroke']);
      expect(detail.body.data.care_receiver.tube_feeding_needs_assistance).toBe(true);
    });
  });

  describe('GET /v1/admin/jobs and /v1/admin/jobs/:id', () => {
    it('lists jobs with pagination meta', async () => {
      await createJob();
      const res = await request(app.getHttpServer())
        .get('/v1/admin/jobs?limit=5')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.meta).toEqual(expect.objectContaining({ page: 1, limit: 5 }));
      expect(res.body.data.length).toBeGreaterThan(0);
    });

    it('returns job detail with the care receiver and an empty applications array before anyone applies', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.id).toBe(job.id);
      expect(res.body.data.applications).toEqual([]);
      expect(res.body.data.care_receiver).toEqual(expect.objectContaining({ mobility: 'walks_independently' }));
    });

    it('returns GEN_002 for a non-existent job', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/jobs/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });
  });

  describe('PATCH /v1/admin/jobs/:id (edit)', () => {
    function editPayload(overrides: Record<string, unknown> = {}) {
      const { care_receiver, ...jobOverrides } = overrides as { care_receiver?: Record<string, unknown> };
      return {
        care_receiver: { ...defaultCareReceiver, ...care_receiver },
        city: 'bangalore',
        area: 'Koramangala',
        description: `${jobDescriptionPrefix} Edited description`,
        duty_type: 'day_duty',
        languages: ['hindi', 'english'],
        salary_monthly: 32000,
        preferred_gender: 'female',
        ...jobOverrides,
      };
    }

    it('updates the job and care receiver in place, same id, and audit-logs it', async () => {
      const job = await createJob();
      fcmService.sendToAllCaregivers.mockClear();

      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload({ care_receiver: { age: 80, toilet_assistance: ['uses_diapers'] } }))
        .expect(200);
      expect(res.body.data.id).toBe(job.id);
      expect(res.body.data.area).toBe('Koramangala');
      expect(res.body.data.duty_type).toBe('day_duty');
      expect(res.body.data.start_time).toBe('08:00:00');
      // Job was already active — editing does not resend the broadcast push.
      expect(fcmService.sendToAllCaregivers).not.toHaveBeenCalled();

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.care_receiver_id).toBe(job.care_receiver_id);
      expect(detail.body.data.care_receiver.age).toBe(80);
      expect(detail.body.data.care_receiver.toilet_assistance).toEqual(['uses_diapers']);
      expect(detail.body.data.languages).toEqual(['hindi', 'english']);

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE entity_type = 'jobs' AND entity_id = $1`,
        [job.id],
      );
      expect(audit.rows.map((r) => r.action)).toContain('job_updated');
    });

    it('reposts a closed job: reopens it and re-broadcasts the "New Job" push', async () => {
      const job = await createJob();
      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/close`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      fcmService.sendToAllCaregivers.mockClear();
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload())
        .expect(200);
      expect(res.body.data.status).toBe('active');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'New Job: Day Duty in Bangalore',
        'Koramangala, Bangalore | IMMEDIATELY APPLY',
      );
      expect(new Date(res.body.data.posted_at).getTime()).toBeGreaterThan(
        new Date(job.posted_at).getTime(),
      );
    });

    it('does NOT bump posted_at when editing an already-active job (only a repost restarts the urgency window)', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload())
        .expect(200);
      expect(res.body.data.status).toBe('active');
      expect(new Date(res.body.data.posted_at).getTime()).toBe(new Date(job.posted_at).getTime());
    });

    it('updates salary_monthly on edit', async () => {
      const job = await createJob({ salary_monthly: 25000 });
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload({ salary_monthly: 40000 }))
        .expect(200);
      expect(res.body.data.salary_monthly).toBe(40000);
    });

    it('leaves existing applications untouched when the job is edited', async () => {
      const job = await createJob();
      const caregiver = await registerCaregiver('0020');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload())
        .expect(200);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.applications).toHaveLength(1);
      expect(detail.body.data.applications[0].status).toBe('applied');
      expect(detail.body.data.applications[0].profile_id).toBe(caregiver.profile_id);
    });

    it('returns GEN_002 for a non-existent job', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/jobs/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload())
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const job = await createJob();
      const caregiver = await registerCaregiver('0021');
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send(editPayload())
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('applies the same validation as create (GEN_001 for an invalid duty_type)', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(editPayload({ duty_type: 'other' }))
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
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
        'Reminder: Live-In Care in Bangalore',
        "Bangalore | APPLY NOW BEFORE IT'S FILLED",
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
      expect(
        res.body.data.find((j: { id: string }) => j.id === activeJob.id).my_application_status,
      ).toBeNull();
    });

    it('includes the full care_receiver (About Patient / Condition details) on every job, not just admin detail', async () => {
      const caregiver = await registerCaregiver('0022');
      const job = await createJob({
        care_receiver: {
          age: 81,
          mobility: 'uses_wheelchair',
          toilet_assistance: ['uses_catheter'],
          requires_vital_monitoring: true,
          vital_monitoring_types: ['blood_pressure'],
        },
      });

      const res = await request(app.getHttpServer())
        .get('/v1/caregiver/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      const listed = res.body.data.find((j: { id: string }) => j.id === job.id);
      expect(listed.care_receiver).toBeDefined();
      expect(listed.care_receiver.age).toBe(81);
      expect(listed.care_receiver.mobility).toBe('uses_wheelchair');
      expect(listed.care_receiver.toilet_assistance).toEqual(['uses_catheter']);
      expect(listed.care_receiver.requires_vital_monitoring).toBe(true);
      expect(listed.care_receiver.vital_monitoring_types).toEqual(['blood_pressure']);
    });
  });

  describe('POST /v1/caregiver/jobs/:id/apply', () => {
    it('rejects a non-available/assigned caregiver (JOB_001)', async () => {
      const caregiver = await registerCaregiver('0003'); // pending_call
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(403);
      expect(res.body.error.code).toBe('JOB_001');
    });

    it('rejects an invalid status value (JOB_004)', async () => {
      const caregiver = await registerCaregiver('0004');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'accepted' }) // admin-only value, not valid from the caregiver endpoint
        .expect(400);
      expect(res.body.error.code).toBe('JOB_004');
    });

    it('rejects applying to a closed job (JOB_002)', async () => {
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
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_002');
    });

    it('records the application, updates in place on re-apply, and shows up in admin job detail', async () => {
      const caregiver = await registerCaregiver('0007');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();

      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const myJobs = await request(app.getHttpServer())
        .get('/v1/caregiver/jobs')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      expect(
        myJobs.body.data.find((j: { id: string }) => j.id === job.id).my_application_status,
      ).toBe('applied');

      // Re-applying (rejecting) updates the same row rather than creating a duplicate.
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'rejected' })
        .expect(200);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.applications).toHaveLength(1);
      expect(detail.body.data.applications[0]).toEqual(
        expect.objectContaining({ status: 'rejected', full_name: 'Jobs Test Subject' }),
      );
    });

    it('allows an assigned caregiver to apply too', async () => {
      const caregiver = await registerCaregiver('0008');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'assigned' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      const job = await createJob();
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
    });

    it('rejects a plain admin token (AUTH_007) — caregiver-jobs routes are caregiver-only', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${job.id}/apply`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'applied' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });

  describe('PATCH /v1/admin/jobs/:jobId/applications/:applicationId', () => {
    async function applyAsAvailableCaregiver(phoneSuffix: string, jobId: string) {
      const caregiver = await registerCaregiver(phoneSuffix);
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      return caregiver;
    }

    it('full flow: accepting one applicant closes the job and assigns the caregiver; a second applicant stays untouched; rejecting the acceptance reopens the job and un-assigns the caregiver', async () => {
      const job = await createJob();
      const caregiverA = await applyAsAvailableCaregiver('0010', job.id);
      const caregiverB = await applyAsAvailableCaregiver('0011', job.id);

      const detailBefore = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const applicationA = detailBefore.body.data.applications.find(
        (a: { profile_id: string }) => a.profile_id === caregiverA.profile_id,
      );
      const applicationB = detailBefore.body.data.applications.find(
        (a: { profile_id: string }) => a.profile_id === caregiverB.profile_id,
      );

      const accept = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/${applicationA.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'accepted' })
        .expect(200);
      expect(accept.body.data).toEqual({ message: 'Application updated', status: 'accepted' });

      const jobAfterAccept = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(jobAfterAccept.body.data.status).toBe('closed');

      const caregiverAStatus = await db.query(
        'SELECT verification_status FROM caregiver_profiles WHERE id = $1',
        [caregiverA.profile_id],
      );
      expect(caregiverAStatus.rows[0].verification_status).toBe('assigned');

      // Second applicant's application is untouched.
      const applicationBAfter = jobAfterAccept.body.data.applications.find(
        (a: { id: string }) => a.id === applicationB.id,
      );
      expect(applicationBAfter.status).toBe('applied');

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE entity_type = 'job_applications' AND entity_id = $1`,
        [applicationA.id],
      );
      expect(audit.rows.map((r) => r.action)).toContain('job_application_decided');

      // Admin reverses the acceptance.
      const reject = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/${applicationA.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'rejected' })
        .expect(200);
      expect(reject.body.data).toEqual({ message: 'Application updated', status: 'rejected' });

      const jobAfterReject = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(jobAfterReject.body.data.status).toBe('active');

      const caregiverAStatusAfter = await db.query(
        'SELECT verification_status FROM caregiver_profiles WHERE id = $1',
        [caregiverA.profile_id],
      );
      expect(caregiverAStatusAfter.rows[0].verification_status).toBe('available');
    });

    it('rejects a still-applied application with no side effects on the job', async () => {
      const job = await createJob();
      const caregiver = await applyAsAvailableCaregiver('0012', job.id);
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const application = detail.body.data.applications.find(
        (a: { profile_id: string }) => a.profile_id === caregiver.profile_id,
      );

      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/${application.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'rejected' })
        .expect(200);

      const jobAfter = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(jobAfter.body.data.status).toBe('active');
    });

    it('returns JOB_006 for a non-existent application', async () => {
      const job = await createJob();
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/00000000-0000-0000-0000-000000000000`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'accepted' })
        .expect(404);
      expect(res.body.error.code).toBe('JOB_006');
    });

    it('returns JOB_007 when accepting an already-accepted application', async () => {
      const job = await createJob();
      const caregiver = await applyAsAvailableCaregiver('0013', job.id);
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const application = detail.body.data.applications.find(
        (a: { profile_id: string }) => a.profile_id === caregiver.profile_id,
      );

      await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/${application.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'accepted' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/${application.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'accepted' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_007');
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const job = await createJob();
      const caregiver = await applyAsAvailableCaregiver('0014', job.id);
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/jobs/${job.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const application = detail.body.data.applications.find(
        (a: { profile_id: string }) => a.profile_id === caregiver.profile_id,
      );

      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/jobs/${job.id}/applications/${application.id}`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'accepted' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });
});
