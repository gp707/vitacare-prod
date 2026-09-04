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
import { AuditLogRetentionService } from '../src/audit-log-retention/audit-log-retention.service';

/**
 * Runs against the real Supabase Postgres instance. Uses the +91700010xxxx
 * test phone range (distinct from every other e2e suite).
 *
 * audit_log_retention_settings is a single GLOBAL singleton row (id fixed
 * to 1), not scoped by phone prefix — same situation as duty_requirements,
 * so this suite follows that exact precedent: snapshot the real row in
 * beforeAll, restore it (including updated_by) in afterAll BEFORE deleting
 * the throwaway admin user, so the row's updated_by FK never dangles.
 */
describe('Audit Log Retention (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let superAdminUserId: string;
  let originalRow: {
    retention_days: number;
    updated_by: string | null;
    updated_at: Date;
  };

  const testPhone = (suffix: string) => `+91700010${suffix}`;

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700010%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700010%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700010%'");
  }

  async function restoreOriginalRow() {
    await db.query(
      `UPDATE audit_log_retention_settings SET retention_days = $1, updated_by = $2, updated_at = $3 WHERE id = 1`,
      [originalRow.retention_days, originalRow.updated_by, originalRow.updated_at],
    );
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupUsers();

    const row = await db.query('SELECT * FROM audit_log_retention_settings WHERE id = 1');
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
    const inserted = await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ($1, $2, $3, 'Audit Log Retention E2E Super Admin', 'super_admin', true)
       RETURNING id`,
      ['audit-log-retention-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    superAdminUserId = inserted.rows[0].id;
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'audit-log-retention-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterEach(async () => {
    // Last-resort safety net in case a test's own reset didn't run.
    await restoreOriginalRow();
  });

  afterAll(async () => {
    try {
      // Must run before cleanupUsers() — the row's updated_by can
      // reference this suite's throwaway admin.
      await restoreOriginalRow();
      await cleanupUsers();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('GET /v1/admin/audit-log-retention', () => {
    it('returns the row with updated_by_name, admin-only', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/audit-log-retention')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.retention_days).toBe(originalRow.retention_days);
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).get('/v1/admin/audit-log-retention').expect(401);
    });
  });

  describe('PATCH /v1/admin/audit-log-retention', () => {
    it('updates the retention window and audit-logs the change', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/audit-log-retention')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ retention_days: 90 })
        .expect(200);
      expect(patch.body.data.retention_days).toBe(90);

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs?action=audit_log_retention_updated')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data.length).toBeGreaterThan(0);
    });

    it('rejects a non-admin token', async () => {
      await request(app.getHttpServer())
        .patch('/v1/admin/audit-log-retention')
        .send({ retention_days: 90 })
        .expect(401);
    });

    it.each([
      ['missing', {}],
      ['zero', { retention_days: 0 }],
      ['negative', { retention_days: -5 }],
      ['not an integer', { retention_days: 12.5 }],
      ['above the 3650 cap', { retention_days: 5000 }],
    ])('rejects retention_days %s with GEN_001', async (_label, body) => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/audit-log-retention')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(body)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });
  });

  describe('AuditLogRetentionService.purgeExpiredLogs', () => {
    it('deletes only rows older than the configured window, leaving newer rows untouched', async () => {
      await db.query(
        `UPDATE audit_log_retention_settings SET retention_days = 30, updated_by = $1, updated_at = NOW() WHERE id = 1`,
        [superAdminUserId],
      );

      const oldInsert = await db.query(
        `INSERT INTO audit_logs (user_id, action, entity_type, created_at)
         VALUES ($1, 'login', 'users', NOW() - INTERVAL '31 days') RETURNING id`,
        [superAdminUserId],
      );
      const recentInsert = await db.query(
        `INSERT INTO audit_logs (user_id, action, entity_type, created_at)
         VALUES ($1, 'login', 'users', NOW() - INTERVAL '1 day') RETURNING id`,
        [superAdminUserId],
      );

      const service = app.get(AuditLogRetentionService);
      await service.purgeExpiredLogs();

      const oldStillThere = await db.query('SELECT 1 FROM audit_logs WHERE id = $1', [oldInsert.rows[0].id]);
      const recentStillThere = await db.query('SELECT 1 FROM audit_logs WHERE id = $1', [
        recentInsert.rows[0].id,
      ]);
      expect(oldStillThere.rowCount).toBe(0);
      expect(recentStillThere.rowCount).toBe(1);

      // Clean up the surviving recent row ourselves — it's outside the
      // window the delete-based cleanupUsers() sweep targets by id alone.
      await db.query('DELETE FROM audit_logs WHERE id = $1', [recentInsert.rows[0].id]);
    });
  });
});
