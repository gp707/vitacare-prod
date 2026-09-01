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

/**
 * Runs against the real Supabase Postgres instance. Uses the
 * +91700009xxxx test phone range (distinct from every other e2e suite).
 *
 * duty_requirements is a single GLOBAL singleton row (id fixed to 1), not
 * scoped by phone prefix — same situation as rate_card/scope_of_work, so
 * this suite follows that exact precedent: snapshot the real row in
 * beforeAll, restore it (including updated_by) in afterAll BEFORE deleting
 * the throwaway admin user, so the row's updated_by FK never dangles.
 */
describe('Duty Requirements (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let originalRow: {
    live_in: string[];
    day_duty: string[];
    night_duty: string[];
    updated_by: string | null;
    updated_at: Date;
  };

  const testPhone = (suffix: string) => `+91700009${suffix}`;

  const validUpdate = {
    live_in: ['New live-in bullet A', 'New live-in bullet B'],
    day_duty: ['New day-duty bullet A', 'New day-duty bullet B'],
    night_duty: ['New night-duty bullet A', 'New night-duty bullet B'],
  };

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700009%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700009%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700009%'");
  }

  async function restoreOriginalRow() {
    await db.query(
      `UPDATE duty_requirements SET live_in = $1, day_duty = $2, night_duty = $3, updated_by = $4, updated_at = $5 WHERE id = 1`,
      [
        originalRow.live_in,
        originalRow.day_duty,
        originalRow.night_duty,
        originalRow.updated_by,
        originalRow.updated_at,
      ],
    );
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupUsers();

    const row = await db.query('SELECT * FROM duty_requirements WHERE id = 1');
    originalRow = row.rows[0];

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
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
       VALUES ($1, $2, $3, 'Duty Requirements E2E Super Admin', 'super_admin', true)`,
      ['duty-requirements-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'duty-requirements-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterEach(async () => {
    // Last-resort safety net in case a test's own reset didn't run.
    await restoreOriginalRow();
  });

  afterAll(async () => {
    try {
      // Must run before cleanupUsers() — duty_requirements.updated_by can
      // reference this suite's throwaway admin.
      await restoreOriginalRow();
      await cleanupUsers();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('GET /v1/duty-requirements (public)', () => {
    it('returns the current duty requirements with no auth required', async () => {
      const res = await request(app.getHttpServer()).get('/v1/duty-requirements').expect(200);
      expect(res.body.data.live_in).toEqual(originalRow.live_in);
      expect(res.body.data.day_duty).toEqual(originalRow.day_duty);
      expect(res.body.data.night_duty).toEqual(originalRow.night_duty);
    });
  });

  describe('GET /v1/admin/duty-requirements', () => {
    it('returns the row with updated_by_name, admin-only', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/duty-requirements')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.live_in).toEqual(originalRow.live_in);
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).get('/v1/admin/duty-requirements').expect(401);
    });
  });

  describe('PATCH /v1/admin/duty-requirements', () => {
    it('updates the duty requirements and it is immediately reflected on the public endpoint', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/duty-requirements')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(validUpdate)
        .expect(200);
      expect(patch.body.data.live_in).toEqual(validUpdate.live_in);
      expect(patch.body.data.day_duty).toEqual(validUpdate.day_duty);
      expect(patch.body.data.night_duty).toEqual(validUpdate.night_duty);

      const publicGet = await request(app.getHttpServer()).get('/v1/duty-requirements').expect(200);
      expect(publicGet.body.data.live_in).toEqual(validUpdate.live_in);
      expect(publicGet.body.data.day_duty).toEqual(validUpdate.day_duty);
      expect(publicGet.body.data.night_duty).toEqual(validUpdate.night_duty);

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs?action=duty_requirements_updated')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data.length).toBeGreaterThan(0);
    });

    it('rejects a non-admin token', async () => {
      await request(app.getHttpServer()).patch('/v1/admin/duty-requirements').send(validUpdate).expect(401);
    });

    it.each([
      ['live_in missing', { day_duty: validUpdate.day_duty, night_duty: validUpdate.night_duty }],
      ['day_duty not an array', { ...validUpdate, day_duty: 'not-an-array' }],
      ['night_duty has a non-string element', { ...validUpdate, night_duty: [1, 2] }],
    ])('rejects %s with GEN_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/duty-requirements')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it.each([
      ['live_in has only a blank bullet', { ...validUpdate, live_in: ['   '] }],
      ['day_duty has a blank bullet', { ...validUpdate, day_duty: ['fine', '   '] }],
    ])('rejects %s with DUTY_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/duty-requirements')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('DUTY_001');
    });
  });
});
