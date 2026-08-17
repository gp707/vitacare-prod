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
 * Runs against the real Supabase Postgres. Uses the +91700003xxxx test
 * phone range (distinct from every other e2e suite). Unlike other suites,
 * app_min_versions is a global 2-row singleton table (one row per
 * platform), not per-test data — so this suite snapshots the real rows in
 * beforeAll and restores them in afterAll instead of deleting anything.
 */
describe('App Versions (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let caregiverToken: string;
  let originalRows: Array<{
    platform: string;
    min_version: string;
    store_url: string | null;
    update_message: string | null;
    updated_by: string | null;
    updated_at: Date;
  }>;

  const testPhone = (suffix: string) => `+91700003${suffix}`;

  async function restoreOriginalRows() {
    for (const row of originalRows) {
      await db.query(
        `UPDATE app_min_versions
         SET min_version = $2, store_url = $3, update_message = $4, updated_by = $5, updated_at = $6
         WHERE platform = $1`,
        [row.platform, row.min_version, row.store_url, row.update_message, row.updated_by, row.updated_at],
      );
    }
  }

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700003%' AND role = 'caregiver'");
    await db.query("DELETE FROM users WHERE phone LIKE '+91700003%'");
  }

  beforeAll(async () => {
    db = new Client({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false },
    });
    await db.connect();
    await cleanupUsers();

    const rows = await db.query('SELECT * FROM app_min_versions');
    originalRows = rows.rows;

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
      .overrideProvider(FcmService)
      .useValue({ sendToUser: jest.fn(), sendToAllCaregivers: jest.fn() })
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
       VALUES ($1, $2, $3, 'App Versions E2E Super Admin', 'super_admin', true)`,
      ['app-versions-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'app-versions-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;

    const caregiverRes = await request(app.getHttpServer()).post('/v1/auth/register').send({
      phone: testPhone('0001'),
      full_name: 'App Versions Test Subject',
      gender: 'female',
      age: 28,
      languages: ['hindi'],
      religion: 'hindu',
      highest_qualification: 'rn_above_2_years',
      terms_accepted: true,
      code: '1234',
    });
    caregiverToken = caregiverRes.body.data.access_token;
  });

  afterAll(async () => {
    await restoreOriginalRows();
    await cleanupUsers();
    await db.end();
    await app.close();
  });

  describe('GET /v1/app-versions/check', () => {
    it('is unauthenticated — no token required', async () => {
      await request(app.getHttpServer())
        .get('/v1/app-versions/check')
        .query({ platform: 'android', version: '1.0.0' })
        .expect(200);
    });

    it('reports update_required with store_url/update_message once min_version is raised above the given version', async () => {
      await request(app.getHttpServer())
        .patch('/v1/admin/app-versions/android')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          min_version: '9.9.9',
          store_url: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
          update_message: 'Please update to continue using NurseJobs.',
        })
        .expect(200);

      const res = await request(app.getHttpServer())
        .get('/v1/app-versions/check')
        .query({ platform: 'android', version: '1.0.0' })
        .expect(200);

      expect(res.body.data).toEqual({
        update_required: true,
        min_version: '9.9.9',
        store_url: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
        update_message: 'Please update to continue using NurseJobs.',
      });
    });

    it('does not require an update, and omits store_url/update_message, once the caller is on min_version or later', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/app-versions/check')
        .query({ platform: 'android', version: '9.9.9' })
        .expect(200);

      expect(res.body.data.update_required).toBe(false);
      expect(res.body.data.store_url).toBeNull();
      expect(res.body.data.update_message).toBeNull();
    });

    it('returns GEN_001 for an unrecognized platform (rejected by DTO validation, same as any other bad query param)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/app-versions/check')
        .query({ platform: 'windows', version: '1.0.0' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('returns GEN_001 for a malformed version string', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/app-versions/check')
        .query({ platform: 'android', version: 'not-a-version' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });
  });

  describe('GET /v1/admin/app-versions', () => {
    it('lists both platform rows for an admin', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/app-versions')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const platforms = res.body.data.map((r: { platform: string }) => r.platform).sort();
      expect(platforms).toEqual(['android', 'ios']);
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/app-versions')
        .set('Authorization', `Bearer ${caregiverToken}`)
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });

  describe('PATCH /v1/admin/app-versions/:platform', () => {
    it('updates min_version/store_url/update_message and audit-logs it, resolving updated_by_name on the next list', async () => {
      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/app-versions/ios')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ min_version: '2.5.0', store_url: 'https://apps.apple.com/app/id0000000000' })
        .expect(200);
      expect(patch.body.data.min_version).toBe('2.5.0');
      expect(patch.body.data.store_url).toBe('https://apps.apple.com/app/id0000000000');

      const list = await request(app.getHttpServer())
        .get('/v1/admin/app-versions')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const iosRow = list.body.data.find((r: { platform: string }) => r.platform === 'ios');
      expect(iosRow.updated_by_name).toBe('App Versions E2E Super Admin');

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE entity_type = 'app_min_versions' AND user_id = (
           SELECT id FROM users WHERE phone = $1
         )`,
        [testPhone('0999')],
      );
      expect(audit.rows.map((r) => r.action)).toContain('app_version_updated');
    });

    it('rejects a malformed min_version (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/app-versions/android')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ min_version: '1.2' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('returns GEN_002 for an unrecognized platform', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/app-versions/windows')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ min_version: '1.0.0' })
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/app-versions/android')
        .set('Authorization', `Bearer ${caregiverToken}`)
        .send({ min_version: '1.0.0' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });
});
