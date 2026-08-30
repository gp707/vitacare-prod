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
 * +91700007xxxx test phone range (distinct from every other e2e suite —
 * see the convention note in auth.e2e-spec.ts).
 *
 * Regression coverage for JwtAuthGuard's existence/is_active re-check on
 * every request (added after a live bug: an admin's still-valid JWT for a
 * since-deleted user crashed PATCH /admin/otp-settings/:app with an
 * unhandled foreign-key-violation 500, because the endpoint stamps
 * `updated_by = user.sub` into a column with a REFERENCES users(id)
 * constraint. The guard now catches this class of bug for every
 * authenticated endpoint, not just that one — these tests exercise both
 * the general behavior (caregiver token) and the exact original scenario
 * (admin token hitting an audit-stamp write).
 */
describe('JwtAuthGuard — deleted/deactivated user re-check (e2e)', () => {
  let app: INestApplication;
  let db: Client;

  const testPhone = (suffix: string) => `+91700007${suffix}`;

  async function cleanup() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700007%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700007%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700007%'");
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

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
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  it('rejects with AUTH_005 (not a 500) when the token is valid but the user row has been deleted', async () => {
    const phone = testPhone('0001');
    const register = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone,
        full_name: 'Ghost Caregiver',
        gender: 'male',
        age: 30,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    const { access_token, user_id } = register.body.data;

    // Simulate the account having been deleted after the token was issued —
    // audit_logs first, same FK-ordering constraint as every other cleanup
    // in this test suite.
    await db.query('DELETE FROM audit_logs WHERE user_id = $1 OR target_user_id = $1', [user_id]);
    await db.query('DELETE FROM users WHERE id = $1', [user_id]);

    const res = await request(app.getHttpServer())
      .get('/v1/caregiver/profile')
      .set('Authorization', `Bearer ${access_token}`)
      .expect(401);
    expect(res.body.error.code).toBe('AUTH_005');
  });

  it('rejects with AUTH_004 when the token is valid but the account has since been deactivated', async () => {
    const phone = testPhone('0002');
    const register = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone,
        full_name: 'Deactivated Caregiver',
        gender: 'male',
        age: 30,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    const { access_token, user_id } = register.body.data;

    await db.query('UPDATE users SET is_active = false WHERE id = $1', [user_id]);

    const res = await request(app.getHttpServer())
      .get('/v1/caregiver/profile')
      .set('Authorization', `Bearer ${access_token}`)
      .expect(401);
    expect(res.body.error.code).toBe('AUTH_004');
  });

  it('reproduces the original bug scenario: a deleted admin\'s token hitting an audit-stamp write now gets a clean AUTH_005 instead of a 500', async () => {
    const passwordHash = await bcrypt.hash('AdminPass123', 4);
    const adminEmail = 'ghost-admin-e2e@e2e-test.local';
    const created = await db.query<{ id: string }>(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ($1, $2, $3, 'Ghost Admin', 'super_admin', true) RETURNING id`,
      [adminEmail, testPhone('0999'), passwordHash],
    );
    const adminId = created.rows[0].id;

    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: adminEmail, password: 'AdminPass123' })
      .expect(200);
    const token = login.body.data.access_token;

    // Delete the admin after login, same as the live scenario this test
    // guards against — a throwaway admin's token outlives the admin row.
    await db.query('DELETE FROM audit_logs WHERE user_id = $1 OR target_user_id = $1', [adminId]);
    await db.query('DELETE FROM users WHERE id = $1', [adminId]);

    const res = await request(app.getHttpServer())
      .patch('/v1/admin/otp-settings/nursejobs')
      .set('Authorization', `Bearer ${token}`)
      .send({ enabled: false })
      .expect(401);
    expect(res.body.error.code).toBe('AUTH_005');
  });

  it('still allows a normal, active user through unaffected', async () => {
    const phone = testPhone('0003');
    const register = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone,
        full_name: 'Normal Caregiver',
        gender: 'male',
        age: 30,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    const { access_token } = register.body.data;

    await request(app.getHttpServer())
      .get('/v1/caregiver/profile')
      .set('Authorization', `Bearer ${access_token}`)
      .expect(200);
  });
});
