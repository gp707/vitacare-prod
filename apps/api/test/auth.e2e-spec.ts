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
 * Runs against the real Supabase Postgres instance configured in apps/api/.env.
 * All rows created here use the +91700000xxxx test phone range, and cleanup
 * is scoped ONLY by that phone prefix (never a broad email-domain match) —
 * e2e spec files run in parallel Jest workers against the same live DB, so a
 * cross-cutting cleanup filter (e.g. "email LIKE '%@e2e-test.local'") can
 * delete another spec file's in-flight rows and cause spurious FK failures.
 */
describe('Auth (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let emailService: { send: jest.Mock; sendToAdmin: jest.Mock };

  const testPhone = (suffix: string) => `+91700000${suffix}`;

  // audit_logs.user_id/target_user_id reference users without ON DELETE
  // CASCADE, so the referencing rows must go first or the user delete
  // 409s on the FK constraint.
  async function cleanup() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700000%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700000%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700000%'");
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

    emailService = { send: jest.fn(), sendToAdmin: jest.fn() };
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      // e2e specs run against real Gmail SMTP creds — stub the transport so
      // running the suite doesn't actually spam vitacasahealthindia@gmail.com.
      .overrideProvider(EmailService)
      .useValue(emailService)
      .compile();
    app = moduleRef.createNestApplication();
    app.enableCors();
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
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('CORS', () => {
    it('answers a cross-origin preflight request (admin-web runs on a different origin than the API)', async () => {
      const res = await request(app.getHttpServer())
        .options('/v1/auth/login/email')
        .set('Origin', 'http://localhost:5050')
        .set('Access-Control-Request-Method', 'POST')
        .set('Access-Control-Request-Headers', 'Content-Type')
        .expect(204);
      expect(res.headers['access-control-allow-origin']).toBeDefined();
    });
  });

  describe('POST /v1/auth/register', () => {
    it('registers a new caregiver with a 4-digit code and returns pending_call', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0001'),
          full_name: 'Ramesh Kumar',
          gender: 'male',
          age: 32,
          languages: ['hindi', 'english'],
          religion: 'hindu',
          code: '1234',
        })
        .expect(201);

      expect(res.body.success).toBe(true);
      expect(res.body.data.verification_status).toBe('pending_call');
      expect(res.body.data.access_token).toBeDefined();
      expect(res.body.data.refresh_token).toBeDefined();
      expect(emailService.sendToAdmin).toHaveBeenCalledWith(
        expect.stringContaining('registration'),
        expect.stringContaining('Ramesh Kumar'),
      );
    });

    it('rejects a duplicate phone with AUTH_001 / 409', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0001'),
          full_name: 'Ramesh Kumar',
          gender: 'male',
          age: 32,
          languages: ['hindi'],
          religion: 'hindu',
          code: '1234',
        })
        .expect(409);

      expect(res.body).toEqual({
        success: false,
        error: { code: 'AUTH_001', message: 'Phone number is already registered' },
      });
    });

    it('rejects invalid age with PROFILE_004 / 400', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0002'),
          full_name: 'Test',
          gender: 'male',
          age: 5,
          languages: ['hindi'],
          religion: 'hindu',
          code: '1234',
        })
        .expect(400);

      expect(res.body.error.code).toBe('PROFILE_004');
    });

    it('rejects a non-4-digit code with PROFILE_016 / 400', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0002'),
          full_name: 'Test',
          gender: 'male',
          age: 30,
          languages: ['hindi'],
          religion: 'hindu',
          code: 'abcd',
        })
        .expect(400);

      expect(res.body.error.code).toBe('PROFILE_016');
    });

    it('rejects a missing code with PROFILE_016 / 400', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0002'),
          full_name: 'Test',
          gender: 'male',
          age: 30,
          languages: ['hindi'],
          religion: 'hindu',
        })
        .expect(400);

      expect(res.body.error.code).toBe('PROFILE_016');
    });

    it('rejects an extra unwhitelisted field with GEN_001 / 400', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0003'),
          full_name: 'Test',
          gender: 'male',
          age: 30,
          languages: ['hindi'],
          religion: 'hindu',
          code: '1234',
          role: 'super_admin',
        })
        .expect(400);

      expect(res.body.error.code).toBe('GEN_001');
    });
  });

  describe('POST /v1/auth/login/code', () => {
    it('logs in immediately after registration with the code set at registration', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '1234' })
        .expect(200);

      expect(res.body.data.access_token).toBeDefined();
      expect(res.body.data.verification_status).toBe('pending_call');
      expect(res.body.data.advanced_details_completed).toBe(false);
    });

    it('returns AUTH_002 / 404 for an unregistered phone', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('9999'), code: '1234' })
        .expect(404);

      expect(res.body.error.code).toBe('AUTH_002');
    });

    it('returns PROFILE_007 / 400 for a malformed phone', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: '12345', code: '1234' })
        .expect(400);

      expect(res.body.error.code).toBe('PROFILE_007');
    });

    it('returns AUTH_008 / 401 for the wrong code', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '0000' })
        .expect(401);

      expect(res.body.error.code).toBe('AUTH_008');
    });

    it('returns PROFILE_016 / 400 for a non-4-digit code', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: 'abcd' })
        .expect(400);

      expect(res.body.error.code).toBe('PROFILE_016');
    });
  });

  describe('POST /v1/auth/login/email (admin)', () => {
    const adminEmail = 'admin-e2e@e2e-test.local';

    beforeAll(async () => {
      const passwordHash = await bcrypt.hash('AdminPass123', 4);
      await db.query(
        `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
         VALUES ($1, $2, $3, 'E2E Admin', 'admin', true)`,
        [adminEmail, testPhone('0100'), passwordHash],
      );
    });

    it('logs in an admin with correct credentials, verification_status is null', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: adminEmail, password: 'AdminPass123' })
        .expect(200);

      expect(res.body.data.access_token).toBeDefined();
      expect(res.body.data.verification_status).toBeNull();
    });

    it('returns AUTH_003 / 401 for wrong password without leaking which field was wrong', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: adminEmail, password: 'WrongPass1' })
        .expect(401);

      expect(res.body.error.code).toBe('AUTH_003');
    });

    it('returns AUTH_003 / 401 for a caregiver attempting email login', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: 'not-an-admin@e2e-test.local', password: 'whatever1' })
        .expect(401);

      expect(res.body.error.code).toBe('AUTH_003');
    });
  });

  describe('refresh + logout', () => {
    it('rotates the refresh token and rejects reuse of the old one', async () => {
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '1234' })
        .expect(200);

      const firstRefreshToken = login.body.data.refresh_token;

      const refreshed = await request(app.getHttpServer())
        .post('/v1/auth/refresh')
        .send({ refresh_token: firstRefreshToken })
        .expect(200);

      expect(refreshed.body.data.access_token).toBeDefined();
      expect(refreshed.body.data.refresh_token).not.toBe(firstRefreshToken);

      const reuse = await request(app.getHttpServer())
        .post('/v1/auth/refresh')
        .send({ refresh_token: firstRefreshToken })
        .expect(401);

      expect(reuse.body.error.code).toBe('AUTH_006');
    });

    it('rejects /auth/logout without a bearer token (AUTH_005)', async () => {
      const res = await request(app.getHttpServer()).post('/v1/auth/logout').expect(401);
      expect(res.body.error.code).toBe('AUTH_005');
    });

    it('logs out with a valid token, then that refresh token stops working', async () => {
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '1234' })
        .expect(200);

      const { access_token, refresh_token } = login.body.data;

      await request(app.getHttpServer())
        .post('/v1/auth/logout')
        .set('Authorization', `Bearer ${access_token}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/auth/refresh')
        .send({ refresh_token })
        .expect(401);

      expect(res.body.error.code).toBe('AUTH_006');
    });
  });
});
