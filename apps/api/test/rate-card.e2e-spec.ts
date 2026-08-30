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
 * +91700007xxxx test phone range (distinct from every other e2e suite).
 *
 * rate_card is a single GLOBAL singleton row (id fixed to 1), not scoped
 * by phone prefix — same situation as otp_auth_settings in
 * otp.e2e-spec.ts, so this suite follows that exact precedent: snapshot
 * the real row in beforeAll, restore it (including updated_by) in
 * afterAll BEFORE deleting the throwaway admin user, so the row's
 * updated_by FK never dangles.
 */
describe('Rate Card (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let originalRow: {
    title: string;
    column_labels: string[];
    row_labels: string[];
    cells: string[][];
    updated_by: string | null;
    updated_at: Date;
  };

  const testPhone = (suffix: string) => `+91700007${suffix}`;

  const validUpdate = {
    title: 'Updated Salary Guidelines',
    column_labels: ['Col A', 'Col B', 'Col C'],
    row_labels: ['Row A', 'Row B', 'Row C'],
    cells: [
      ['a1', 'a2', 'a3'],
      ['b1', 'b2', 'b3'],
      ['c1', 'c2', 'c3'],
    ],
  };

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700007%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700007%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700007%'");
  }

  async function restoreOriginalRow() {
    await db.query(
      `UPDATE rate_card SET title = $1, column_labels = $2, row_labels = $3, cells = $4, updated_by = $5, updated_at = $6 WHERE id = 1`,
      [
        originalRow.title,
        originalRow.column_labels,
        originalRow.row_labels,
        JSON.stringify(originalRow.cells),
        originalRow.updated_by,
        originalRow.updated_at,
      ],
    );
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupUsers();

    const row = await db.query('SELECT * FROM rate_card WHERE id = 1');
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
       VALUES ($1, $2, $3, 'Rate Card E2E Super Admin', 'super_admin', true)`,
      ['rate-card-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'rate-card-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterEach(async () => {
    // Last-resort safety net in case a test's own reset didn't run.
    await restoreOriginalRow();
  });

  afterAll(async () => {
    try {
      // Must run before cleanupUsers() — rate_card.updated_by can
      // reference this suite's throwaway admin.
      await restoreOriginalRow();
      await cleanupUsers();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('GET /v1/rate-card (public)', () => {
    it('returns the current rate card with no auth required', async () => {
      const res = await request(app.getHttpServer()).get('/v1/rate-card').expect(200);
      expect(res.body.data.title).toBe(originalRow.title);
      expect(res.body.data.column_labels).toEqual(originalRow.column_labels);
      expect(res.body.data.row_labels).toEqual(originalRow.row_labels);
      expect(res.body.data.cells).toEqual(originalRow.cells);
    });
  });

  describe('GET /v1/admin/rate-card', () => {
    it('returns the row with updated_by_name, admin-only', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/rate-card')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.title).toBe(originalRow.title);
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).get('/v1/admin/rate-card').expect(401);
    });
  });

  describe('PATCH /v1/admin/rate-card', () => {
    it('updates the rate card and it is immediately reflected on the public endpoint', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(validUpdate)
        .expect(200);
      expect(patch.body.data.title).toBe(validUpdate.title);
      expect(patch.body.data.cells).toEqual(validUpdate.cells);

      const publicGet = await request(app.getHttpServer()).get('/v1/rate-card').expect(200);
      expect(publicGet.body.data.title).toBe(validUpdate.title);
      expect(publicGet.body.data.column_labels).toEqual(validUpdate.column_labels);
      expect(publicGet.body.data.row_labels).toEqual(validUpdate.row_labels);
      expect(publicGet.body.data.cells).toEqual(validUpdate.cells);

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs?action=rate_card_updated')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data.length).toBeGreaterThan(0);
    });

    it('rejects a non-admin token', async () => {
      await request(app.getHttpServer()).patch('/v1/admin/rate-card').send(validUpdate).expect(401);
    });

    it.each([
      ['only 2 column_labels', { ...validUpdate, column_labels: ['A', 'B'] }],
      ['4 row_labels', { ...validUpdate, row_labels: ['A', 'B', 'C', 'D'] }],
      ['an empty title', { ...validUpdate, title: '' }],
    ])('rejects %s with GEN_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it.each([
      ['only 2 rows', [validUpdate.cells[0], validUpdate.cells[1]]],
      ['a row with only 2 columns', [['a', 'b'], validUpdate.cells[1], validUpdate.cells[2]]],
    ])('rejects malformed cells (%s) with RATE_001', async (_label, cells) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ ...validUpdate, cells })
        .expect(400);
      expect(res.body.error.code).toBe('RATE_001');
    });
  });
});
