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
 * Actionable Error Logs (request data, affected users, resolve workflow).
 * Runs against the real Supabase Postgres instance, uses the +91700015xxxx
 * test phone range, and seeds error_logs rows directly so it never has to
 * crash the server to get one. Every seeded row is tagged with the path
 * prefix /v1/e2e-actionable so cleanup never touches anyone else's rows.
 */
describe('Error Logs — actionable (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let adminToken: string;
  let adminId: string;
  let patientToken: string;
  let patientId: string;
  let orgId: string;
  const PATH = '/v1/e2e-actionable';

  async function cleanup() {
    const users = `(SELECT id FROM users WHERE phone LIKE '+91700015%')`;
    await db.query(`DELETE FROM error_logs WHERE path LIKE '${PATH}%' OR user_id IN ${users}`);
    await db.query(`DELETE FROM audit_logs WHERE user_id IN ${users} OR target_user_id IN ${users}`);
    await db.query(`DELETE FROM individual_profiles WHERE user_id IN ${users}`);
    await db.query(`DELETE FROM organisation_profiles WHERE user_id IN ${users}`);
    await db.query(`DELETE FROM users WHERE phone LIKE '+91700015%'`);
  }

  async function seed(opts: {
    userId: string | null;
    role?: string | null;
    message: string;
    pathSuffix?: string;
    ageMinutes?: number;
    status?: 'open' | 'resolved';
    context?: object | null;
  }) {
    const res = await db.query(
      `INSERT INTO error_logs (method, path, status_code, message, stack, user_id, user_role, ip_address, request_context, user_agent, status, created_at)
       VALUES ('POST', $1, 500, $2, 'stack...', $3, $4, '203.0.113.9', $5, 'Dart/3.6 (dart:io)', $6, NOW() - ($7 || ' minutes')::interval)
       RETURNING id`,
      [
        `${PATH}${opts.pathSuffix ?? ''}`,
        opts.message,
        opts.userId,
        opts.role ?? null,
        opts.context === undefined ? JSON.stringify({ body: { phone: '+9170001500xx' } }) : opts.context && JSON.stringify(opts.context),
        opts.status ?? 'open',
        String(opts.ageMinutes ?? 5),
      ],
    );
    return res.rows[0].id as string;
  }

  const adminGet = (path: string) =>
    request(app.getHttpServer()).get(`/v1/admin/error-logs${path}`).set('Authorization', `Bearer ${adminToken}`);
  const adminPatch = (path: string, body: object = {}) =>
    request(app.getHttpServer()).patch(`/v1/admin/error-logs${path}`).set('Authorization', `Bearer ${adminToken}`).send(body);

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
      .overrideProvider(FcmService)
      .useValue({ sendToUser: jest.fn(), sendToAllCaregivers: jest.fn(), sendToTokens: jest.fn() })
      .compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('v1');
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true, exceptionFactory: validationExceptionFactory }),
    );
    app.useGlobalFilters(new GlobalExceptionFilter());
    app.useGlobalInterceptors(new TransformInterceptor());
    await app.init();

    const passwordHash = await bcrypt.hash('AdminPass123', 4);
    const admin = await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ('error-logs-admin-e2e@e2e-test.local', '+917000150999', $1, 'Error Logs E2E Admin', 'super_admin', true) RETURNING id`,
      [passwordHash],
    );
    adminId = admin.rows[0].id;
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'error-logs-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    adminToken = login.body.data.access_token;

    const patient = await request(app.getHttpServer())
      .post('/v1/auth/register/individual')
      .send({ phone: '+917000150001', full_name: 'Errors Patient', terms_accepted: true, code: '1234' })
      .expect(201);
    patientId = patient.body.data.user_id;
    patientToken = patient.body.data.access_token;

    const org = await request(app.getHttpServer())
      .post('/v1/auth/register/organisation')
      .send({
        phone: '+917000150002',
        code: '1234',
        organisation_name: 'Errors Hospital',
        contact_person_name: 'Errors Contact',
        organisation_type: 'hospital',
        city: 'bangalore',
        terms_accepted: true,
      })
      .expect(201);
    orgId = org.body.data.user_id;
  });

  afterAll(async () => {
    try {
      await cleanup();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('access control', () => {
    it('rejects unauthenticated and non-admin callers on every new endpoint', async () => {
      const anyId = '11111111-1111-4111-8111-111111111111';
      const calls: [string, string][] = [
        ['get', '/v1/admin/error-logs/affected-users'],
        ['patch', `/v1/admin/error-logs/${anyId}/resolve`],
        ['patch', `/v1/admin/error-logs/users/${anyId}/resolve`],
      ];
      for (const [method, url] of calls) {
        await (request(app.getHttpServer()) as any)[method](url).expect(401);
        await (request(app.getHttpServer()) as any)[method](url).set('Authorization', `Bearer ${patientToken}`).expect(403);
      }
    });
  });

  describe('GET /v1/admin/error-logs', () => {
    it('returns the sanitized request data, user agent and who resolved it, and the customer identity', async () => {
      const id = await seed({
        userId: patientId,
        role: 'individual',
        message: 'column "x" does not exist',
        context: { body: { phone: '+917000150001', code: '[redacted]', care_receiver: { age: 74 } }, query: { page: '1' } },
      });
      const res = await adminGet(`?search=${encodeURIComponent('does not exist')}&user_id=${patientId}&limit=100`).expect(200);
      const row = res.body.data.find((r: any) => r.id === id);
      expect(row).toMatchObject({
        user_full_name: 'Errors Patient',
        user_phone: '+917000150001',
        status: 'open',
        user_agent: 'Dart/3.6 (dart:io)',
        request_context: { body: { phone: '+917000150001', code: '[redacted]', care_receiver: { age: 74 } }, query: { page: '1' } },
        resolved_by_name: null,
      });
      expect(typeof row.patient_number).toBe('number');
    });

    it('filters by status, user and search, and defaults to everything', async () => {
      const openId = await seed({ userId: patientId, role: 'individual', message: 'open one', pathSuffix: '/a' });
      const doneId = await seed({ userId: patientId, role: 'individual', message: 'done one', pathSuffix: '/b', status: 'resolved' });
      const otherId = await seed({ userId: orgId, role: 'organisation', message: 'org one', pathSuffix: '/c' });

      const all = await adminGet(`?search=${encodeURIComponent(PATH)}&limit=100`).expect(200);
      const allIds = all.body.data.map((r: any) => r.id);
      expect(allIds).toEqual(expect.arrayContaining([openId, doneId, otherId]));

      const open = await adminGet(`?status=open&search=${encodeURIComponent(PATH)}&limit=100`).expect(200);
      const openIds = open.body.data.map((r: any) => r.id);
      expect(openIds).toContain(openId);
      expect(openIds).not.toContain(doneId);

      const resolved = await adminGet(`?status=resolved&search=${encodeURIComponent(PATH)}&limit=100`).expect(200);
      expect(resolved.body.data.map((r: any) => r.id)).toContain(doneId);
      expect(resolved.body.data.every((r: any) => r.status === 'resolved')).toBe(true);

      const mine = await adminGet(`?user_id=${patientId}&limit=100`).expect(200);
      expect(mine.body.data.every((r: any) => r.user_id === patientId)).toBe(true);
      expect(mine.body.data.map((r: any) => r.id)).not.toContain(otherId);
      // The count query applies the same filters as the list query.
      expect(mine.body.meta.total).toBe(mine.body.data.length);
    });

    it('rejects invalid filter values', async () => {
      await adminGet('?status=weird').expect(400);
      await adminGet('?user_id=not-a-uuid').expect(400);
    });
  });

  describe('GET /v1/admin/error-logs/affected-users', () => {
    it('lists each person once with count, last error and the phone to call; anonymous errors are not included', async () => {
      await cleanupSeeds();
      await seed({ userId: patientId, role: 'individual', message: 'older failure', pathSuffix: '/old', ageMinutes: 60 });
      await seed({ userId: patientId, role: 'individual', message: 'newest failure', pathSuffix: '/new', ageMinutes: 2 });
      await seed({ userId: orgId, role: 'organisation', message: 'org failure', pathSuffix: '/org', ageMinutes: 30 });
      await seed({ userId: null, message: 'anonymous failure', pathSuffix: '/anon' });

      const res = await adminGet('/affected-users?limit=100').expect(200);
      const mine = res.body.data.filter((r: any) => [patientId, orgId].includes(r.user_id));
      expect(mine).toHaveLength(2);
      // Most recently affected first.
      expect(mine[0].user_id).toBe(patientId);
      expect(mine[0]).toMatchObject({
        full_name: 'Errors Patient',
        phone: '+917000150001',
        role: 'individual',
        error_count: 2,
        open_count: 2,
        last_message: 'newest failure',
      });
      expect(mine[0].last_request).toBe(`POST ${PATH}/new`);
      expect(typeof mine[0].patient_number).toBe('number');
      expect(mine[1]).toMatchObject({ user_id: orgId, role: 'organisation', error_count: 1, organisation_name: 'Errors Hospital' });
      expect(typeof mine[1].org_number).toBe('number');
      // No row for an anonymous error.
      expect(res.body.data.every((r: any) => r.user_id)).toBe(true);
      expect(res.body.meta.total).toBe(res.body.data.length);
    });

    it('drops a person once all their errors are resolved (default open view), unless asked for all', async () => {
      await cleanupSeeds();
      await seed({ userId: patientId, role: 'individual', message: 'handled', status: 'resolved' });
      const open = await adminGet('/affected-users?limit=100').expect(200);
      expect(open.body.data.some((r: any) => r.user_id === patientId)).toBe(false);
      const all = await adminGet('/affected-users?status=all&limit=100').expect(200);
      const entry = all.body.data.find((r: any) => r.user_id === patientId);
      expect(entry).toMatchObject({ error_count: 1, open_count: 0 });
    });

    it('rejects an invalid status', async () => {
      await adminGet('/affected-users?status=weird').expect(400);
    });
  });

  describe('resolve', () => {
    it('resolves one error, records who/when/note, audit-logs it, and is idempotent', async () => {
      await cleanupSeeds();
      const id = await seed({ userId: patientId, role: 'individual', message: 'to resolve' });

      const first = await adminPatch(`/${id}/resolve`, { note: 'Called, re-registered them' }).expect(200);
      expect(first.body.data.message).toBe('Error marked resolved');

      const row = (await adminGet(`?user_id=${patientId}&status=resolved&limit=100`).expect(200)).body.data.find((r: any) => r.id === id);
      expect(row).toMatchObject({
        status: 'resolved',
        resolution_note: 'Called, re-registered them',
        resolved_by: adminId,
        resolved_by_name: 'Error Logs E2E Admin',
      });
      expect(row.resolved_at).toBeTruthy();

      const again = await adminPatch(`/${id}/resolve`, { note: 'second time' }).expect(200);
      expect(again.body.data.message).toBe('Error was already resolved');
      const audits = await db.query(
        `SELECT after_value FROM audit_logs WHERE action = 'error_log_resolved' AND entity_id = $1`,
        [id],
      );
      expect(audits.rows).toHaveLength(1);
      expect(audits.rows[0].after_value).toEqual({ note: 'Called, re-registered them' });
      // The first note is kept; the no-op second call did not overwrite it.
      const check = await db.query('SELECT resolution_note FROM error_logs WHERE id = $1', [id]);
      expect(check.rows[0].resolution_note).toBe('Called, re-registered them');
    });

    it('404s for an unknown id and 400s for a malformed one', async () => {
      await adminPatch('/11111111-1111-4111-8111-111111111111/resolve').expect(404);
      await adminPatch('/not-a-uuid/resolve').expect(400);
    });

    it('rejects an over-long note', async () => {
      const id = await seed({ userId: patientId, role: 'individual', message: 'note too long' });
      await adminPatch(`/${id}/resolve`, { note: 'x'.repeat(1001) }).expect(400);
    });

    it('resolves every open error for one person at once ("I called them") and reports the count', async () => {
      await cleanupSeeds();
      await seed({ userId: patientId, role: 'individual', message: 'e1', pathSuffix: '/1' });
      await seed({ userId: patientId, role: 'individual', message: 'e2', pathSuffix: '/2' });
      await seed({ userId: patientId, role: 'individual', message: 'already', pathSuffix: '/3', status: 'resolved' });
      const otherOrg = await seed({ userId: orgId, role: 'organisation', message: 'not theirs', pathSuffix: '/4' });

      const res = await adminPatch(`/users/${patientId}/resolve`, { note: 'Phoned them' }).expect(200);
      expect(res.body.data.resolved_count).toBe(2);

      const mine = await adminGet(`?user_id=${patientId}&limit=100`).expect(200);
      expect(mine.body.data.every((r: any) => r.status === 'resolved')).toBe(true);
      // Someone else's error is untouched.
      const other = await db.query('SELECT status FROM error_logs WHERE id = $1', [otherOrg]);
      expect(other.rows[0].status).toBe('open');
      const audits = await db.query(
        `SELECT after_value FROM audit_logs WHERE action = 'error_log_resolved' AND target_user_id = $1 AND entity_id IS NULL`,
        [patientId],
      );
      expect(audits.rows).toHaveLength(1);
      expect(audits.rows[0].after_value).toEqual({ note: 'Phoned them', resolved_count: 2 });

      const none = await adminPatch(`/users/${patientId}/resolve`).expect(200);
      expect(none.body.data.resolved_count).toBe(0);
    });
  });

  async function cleanupSeeds() {
    await db.query(`DELETE FROM error_logs WHERE path LIKE '${PATH}%'`);
    await db.query(`DELETE FROM audit_logs WHERE action = 'error_log_resolved' AND user_id = $1`, [adminId]);
  }
});
