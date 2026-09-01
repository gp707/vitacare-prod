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
 * rate_card has one row per frequency ('daily'/'monthly', a DB CHECK) —
 * same "one row per key" situation as app_min_versions (platform), not
 * scoped by phone prefix — so this suite follows that precedent: snapshot
 * both real rows in beforeAll, restore both (including updated_by) in
 * afterAll BEFORE deleting the throwaway admin user, so neither row's
 * updated_by FK ever dangles.
 */
describe('Rate Card (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let originalRows: Record<
    string,
    { title: string; column_labels: string[]; row_labels: string[]; cells: string[][]; updated_by: string | null; updated_at: Date }
  >;

  const testPhone = (suffix: string) => `+91700007${suffix}`;

  const validUpdate = {
    title: 'Updated Daily Guidelines',
    column_labels: ['Col A', 'Col B', 'Col C'],
    row_labels: ['Row A'],
    cells: [['a1', 'a2', 'a3']],
  };

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700007%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700007%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700007%'");
  }

  async function restoreOriginalRows() {
    for (const frequency of Object.keys(originalRows)) {
      const row = originalRows[frequency];
      await db.query(
        `UPDATE rate_card SET title = $2, column_labels = $3, row_labels = $4, cells = $5, updated_by = $6, updated_at = $7 WHERE frequency_of_care = $1`,
        [frequency, row.title, row.column_labels, row.row_labels, JSON.stringify(row.cells), row.updated_by, row.updated_at],
      );
    }
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupUsers();

    const rows = await db.query('SELECT * FROM rate_card ORDER BY frequency_of_care');
    originalRows = {};
    for (const row of rows.rows) originalRows[row.frequency_of_care] = row;

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
    await restoreOriginalRows();
  });

  afterAll(async () => {
    try {
      // Must run before cleanupUsers() — rate_card.updated_by can
      // reference this suite's throwaway admin.
      await restoreOriginalRows();
      await cleanupUsers();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('GET /v1/rate-card (public)', () => {
    it('returns both frequency rows with no auth required', async () => {
      const res = await request(app.getHttpServer()).get('/v1/rate-card').expect(200);
      expect(res.body.data).toHaveLength(2);
      const byFrequency = Object.fromEntries(res.body.data.map((r: any) => [r.frequency_of_care, r]));
      expect(byFrequency.daily.title).toBe(originalRows.daily.title);
      expect(byFrequency.daily.cells).toEqual(originalRows.daily.cells);
      expect(byFrequency.monthly.title).toBe(originalRows.monthly.title);
      expect(byFrequency.monthly.cells).toEqual(originalRows.monthly.cells);
    });
  });

  describe('GET /v1/admin/rate-card', () => {
    it('returns both rows with updated_by_name, admin-only', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/rate-card')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data).toHaveLength(2);
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).get('/v1/admin/rate-card').expect(401);
    });
  });

  describe('PATCH /v1/admin/rate-card/:frequency', () => {
    it('updates only the daily row, leaving monthly untouched, immediately reflected on the public endpoint', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card/daily')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(validUpdate)
        .expect(200);
      expect(patch.body.data.frequency_of_care).toBe('daily');
      expect(patch.body.data.title).toBe(validUpdate.title);
      expect(patch.body.data.cells).toEqual(validUpdate.cells);

      const publicGet = await request(app.getHttpServer()).get('/v1/rate-card').expect(200);
      const byFrequency = Object.fromEntries(publicGet.body.data.map((r: any) => [r.frequency_of_care, r]));
      expect(byFrequency.daily.title).toBe(validUpdate.title);
      expect(byFrequency.monthly.title).toBe(originalRows.monthly.title);
      expect(byFrequency.monthly.cells).toEqual(originalRows.monthly.cells);

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs?action=rate_card_updated')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data.length).toBeGreaterThan(0);
    });

    it('updates the monthly row independently of daily', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card/monthly')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ ...validUpdate, title: 'Updated Monthly Guidelines' })
        .expect(200);
      expect(patch.body.data.frequency_of_care).toBe('monthly');
      expect(patch.body.data.title).toBe('Updated Monthly Guidelines');
    });

    it('rejects an unrecognized frequency (GEN_002)', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card/yearly')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(validUpdate)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('rejects a non-admin token', async () => {
      await request(app.getHttpServer()).patch('/v1/admin/rate-card/daily').send(validUpdate).expect(401);
    });

    it.each([
      ['only 2 column_labels', { ...validUpdate, column_labels: ['A', 'B'] }],
      ['2 row_labels', { ...validUpdate, row_labels: ['A', 'B'] }],
      ['an empty title', { ...validUpdate, title: '' }],
    ])('rejects %s with GEN_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card/daily')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it.each([
      ['2 rows', [validUpdate.cells[0], ['b1', 'b2', 'b3']]],
      ['a row with only 2 columns', [['a', 'b']]],
    ])('rejects malformed cells (%s) with RATE_001', async (_label, cells) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/rate-card/daily')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ ...validUpdate, cells })
        .expect(400);
      expect(res.body.error.code).toBe('RATE_001');
    });
  });
});
