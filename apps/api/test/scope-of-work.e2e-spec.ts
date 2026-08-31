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
 * +91700008xxxx test phone range (distinct from every other e2e suite).
 *
 * scope_of_work is a single GLOBAL singleton row (id fixed to 1), not
 * scoped by phone prefix — same situation as rate_card in
 * rate-card.e2e-spec.ts, so this suite follows that exact precedent:
 * snapshot the real row in beforeAll, restore it (including updated_by) in
 * afterAll BEFORE deleting the throwaway admin user, so the row's
 * updated_by FK never dangles.
 */
describe('Scope of Work (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let originalRow: {
    companion_care: string[];
    bedside_care: string[];
    critical_care: string[];
    updated_by: string | null;
    updated_at: Date;
  };

  const testPhone = (suffix: string) => `+91700008${suffix}`;

  const validUpdate = {
    companion_care: ['New companion bullet A', 'New companion bullet B'],
    bedside_care: ['New bedside bullet A', 'New bedside bullet B'],
    critical_care: ['New critical bullet A', 'New critical bullet B'],
  };

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700008%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700008%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700008%'");
  }

  async function restoreOriginalRow() {
    await db.query(
      `UPDATE scope_of_work SET companion_care = $1, bedside_care = $2, critical_care = $3, updated_by = $4, updated_at = $5 WHERE id = 1`,
      [
        originalRow.companion_care,
        originalRow.bedside_care,
        originalRow.critical_care,
        originalRow.updated_by,
        originalRow.updated_at,
      ],
    );
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupUsers();

    const row = await db.query('SELECT * FROM scope_of_work WHERE id = 1');
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
       VALUES ($1, $2, $3, 'Scope of Work E2E Super Admin', 'super_admin', true)`,
      ['scope-of-work-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'scope-of-work-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterEach(async () => {
    // Last-resort safety net in case a test's own reset didn't run.
    await restoreOriginalRow();
  });

  afterAll(async () => {
    try {
      // Must run before cleanupUsers() — scope_of_work.updated_by can
      // reference this suite's throwaway admin.
      await restoreOriginalRow();
      await cleanupUsers();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('GET /v1/scope-of-work (public)', () => {
    it('returns the current scope of work with no auth required', async () => {
      const res = await request(app.getHttpServer()).get('/v1/scope-of-work').expect(200);
      expect(res.body.data.companion_care).toEqual(originalRow.companion_care);
      expect(res.body.data.bedside_care).toEqual(originalRow.bedside_care);
      expect(res.body.data.critical_care).toEqual(originalRow.critical_care);
    });
  });

  describe('GET /v1/admin/scope-of-work', () => {
    it('returns the row with updated_by_name, admin-only', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/scope-of-work')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.companion_care).toEqual(originalRow.companion_care);
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).get('/v1/admin/scope-of-work').expect(401);
    });
  });

  describe('PATCH /v1/admin/scope-of-work', () => {
    it('updates the scope of work and it is immediately reflected on the public endpoint', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/scope-of-work')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(validUpdate)
        .expect(200);
      expect(patch.body.data.companion_care).toEqual(validUpdate.companion_care);
      expect(patch.body.data.bedside_care).toEqual(validUpdate.bedside_care);
      expect(patch.body.data.critical_care).toEqual(validUpdate.critical_care);

      const publicGet = await request(app.getHttpServer()).get('/v1/scope-of-work').expect(200);
      expect(publicGet.body.data.companion_care).toEqual(validUpdate.companion_care);
      expect(publicGet.body.data.bedside_care).toEqual(validUpdate.bedside_care);
      expect(publicGet.body.data.critical_care).toEqual(validUpdate.critical_care);

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs?action=scope_of_work_updated')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data.length).toBeGreaterThan(0);
    });

    it('rejects a non-admin token', async () => {
      await request(app.getHttpServer()).patch('/v1/admin/scope-of-work').send(validUpdate).expect(401);
    });

    it.each([
      ['companion_care missing', { bedside_care: validUpdate.bedside_care, critical_care: validUpdate.critical_care }],
      ['bedside_care not an array', { ...validUpdate, bedside_care: 'not-an-array' }],
      ['critical_care has a non-string element', { ...validUpdate, critical_care: [1, 2] }],
    ])('rejects %s with GEN_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/scope-of-work')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it.each([
      ['companion_care has only a blank bullet', { ...validUpdate, companion_care: ['   '] }],
      ['bedside_care has a blank bullet', { ...validUpdate, bedside_care: ['fine', '   '] }],
    ])('rejects %s with SCOPE_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/scope-of-work')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('SCOPE_001');
    });
  });
});
