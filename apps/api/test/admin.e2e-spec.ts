import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import { createClient } from '@supabase/supabase-js';
import * as bcrypt from 'bcrypt';
import { AppModule } from '../src/app.module';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { TransformInterceptor } from '../src/common/interceptors/transform.interceptor';
import { validationExceptionFactory } from '../src/common/pipes/validation-exception.factory';
import { EmailService } from '../src/email/email.service';
import { FcmService } from '../src/fcm/fcm.service';

/**
 * Runs against the real Supabase Postgres. Uses the +91700003xxxx test
 * phone range (distinct from every other e2e suite). Cleanup is scoped
 * ONLY by that phone prefix — e2e spec files run in parallel Jest workers
 * against the same live DB, so a broad filter like "email LIKE
 * '%@e2e-test.local'" would delete another spec file's in-flight rows and
 * cause spurious FK failures. Caregiver-role test users must be deleted
 * BEFORE admin-role ones — caregiver_profiles.verified_by references users
 * without ON DELETE CASCADE.
 */
describe('Admin (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let superAdminId: string;
  let regularAdminToken: string;
  let fcmService: { sendToUser: jest.Mock };
  const storage = createClient(
    process.env.SUPABASE_URL as string,
    process.env.SUPABASE_SERVICE_ROLE_KEY as string,
  );
  const uploadedStoragePaths: string[] = [];

  const testPhone = (suffix: string) => `+91700003${suffix}`;

  async function cleanup() {
    // audit_logs.user_id/target_user_id reference users without ON DELETE
    // CASCADE, so the referencing rows must go first or the user deletes
    // below 409 on the FK constraint.
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700003%')`,
    );
    await db.query(
      "DELETE FROM users WHERE phone LIKE '+91700003%' AND role = 'caregiver'",
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700003%'");
  }

  async function registerCaregiver(phoneSuffix: string, fullName = 'Admin E2E Subject') {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: testPhone(phoneSuffix),
        full_name: fullName,
        gender: 'male',
        age: 29,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      });
    return res.body.data as { user_id: string; profile_id: string };
  }

  beforeAll(async () => {
    db = new Client({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false },
    });
    await db.connect();
    await cleanup();

    fcmService = { sendToUser: jest.fn() };
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
    const superAdminResult = await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ($1, $2, $3, 'E2E Super Admin', 'super_admin', true) RETURNING id`,
      ['super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    superAdminId = superAdminResult.rows[0].id;

    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    if (uploadedStoragePaths.length > 0) {
      await storage.storage.from('caregiver-documents').remove(uploadedStoragePaths);
    }
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('RBAC', () => {
    it('blocks a caregiver token from any /admin/* route (AUTH_007)', async () => {
      const caregiver = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({
          phone: testPhone('0001'),
          full_name: 'Rbac Subject',
          gender: 'male',
          age: 30,
          languages: ['hindi'],
          religion: 'hindu',
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
          code: '1234',
        });
      const res = await request(app.getHttpServer())
        .get('/v1/admin/dashboard/stats')
        .set('Authorization', `Bearer ${caregiver.body.data.access_token}`)
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('blocks a plain admin from /admin/users (super_admin only)', async () => {
      const passwordHash = await bcrypt.hash('AdminPass123', 4);
      await db.query(
        `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
         VALUES ($1, $2, $3, 'E2E Regular Admin', 'admin', true)`,
        ['regular-admin-e2e@e2e-test.local', testPhone('0998'), passwordHash],
      );
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: 'regular-admin-e2e@e2e-test.local', password: 'AdminPass123' })
        .expect(200);
      regularAdminToken = login.body.data.access_token;

      const dashboardRes = await request(app.getHttpServer())
        .get('/v1/admin/dashboard/stats')
        .set('Authorization', `Bearer ${regularAdminToken}`)
        .expect(200);
      expect(dashboardRes.body.success).toBe(true);

      const usersRes = await request(app.getHttpServer())
        .get('/v1/admin/users')
        .set('Authorization', `Bearer ${regularAdminToken}`)
        .expect(403);
      expect(usersRes.body.error.code).toBe('AUTH_007');
    });
  });

  describe('Dashboard + caregiver list/detail', () => {
    it('reflects a fresh registration in stats and the list', async () => {
      const before = await request(app.getHttpServer())
        .get('/v1/admin/dashboard/stats')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const beforeTotal = before.body.data.total_caregivers;

      const created = await registerCaregiver('0002', 'Dashboard Subject');

      const after = await request(app.getHttpServer())
        .get('/v1/admin/dashboard/stats')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(after.body.data.total_caregivers).toBe(beforeTotal + 1);
      expect(after.body.data.pending_call).toBeGreaterThanOrEqual(1);

      const list = await request(app.getHttpServer())
        .get('/v1/admin/caregivers?search=Dashboard Subject')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(list.body.data).toHaveLength(1);
      expect(list.body.data[0].profile_id).toBe(created.profile_id);
      expect(list.body.meta.total).toBe(1);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${created.profile_id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.full_name).toBe('Dashboard Subject');
      expect(detail.body.data.admin_notes).toEqual({
        internal_notes: null,
        availability_remarks: null,
      });
    });

    it('returns PROFILE_019 for a nonexistent profile id', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/caregivers/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('PROFILE_019');
    });

    it('rejects invalid pagination (GEN_005)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/caregivers?limit=999')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_005');
    });
  });

  describe('Status transitions', () => {
    it('walks pending_call -> available in a single admin approval, with notes', async () => {
      const { profile_id: profileId } = await registerCaregiver('0003', 'Workflow Subject');

      const notes = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/notes`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ internal_notes: 'Looks good' })
        .expect(200);
      expect(notes.body.data.message).toBe('Notes saved');

      const approve = await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'available' })
        .expect(200);
      expect(approve.body.data.verification_status).toBe('available');
      expect(fcmService.sendToUser).toHaveBeenCalledTimes(1);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.verified_at).not.toBeNull();
      expect(detail.body.data.admin_notes.internal_notes).toBe('Looks good');
    });

    it('admin override: allows jumping directly from pending_call to available, no transition-matrix restriction', async () => {
      const { profile_id: profileId } = await registerCaregiver('0004', 'Override Transition Subject');
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'available' })
        .expect(200);
      expect(res.body.data.verification_status).toBe('available');

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.verified_at).not.toBeNull();
    });

    it('admin override: also allows jumping straight to assigned, and rejects an unknown status value with ADMIN_001', async () => {
      const { profile_id: profileId } = await registerCaregiver('0021', 'Override Assigned Subject');
      const toAssigned = await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'assigned' })
        .expect(200);
      expect(toAssigned.body.data.verification_status).toBe('assigned');

      const invalidValue = await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'not_a_real_status' })
        .expect(400);
      expect(invalidValue.body.error.code).toBe('ADMIN_001');
    });

    it('rejects with a message, persists rejection_message, and enforces the length limit', async () => {
      const { profile_id: profileId } = await registerCaregiver('0005', 'Reject Subject');

      const rejected = await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'rejected', rejection_message: 'Aadhaar not legible' })
        .expect(200);
      expect(rejected.body.data.verification_status).toBe('rejected');

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.rejection_message).toBe('Aadhaar not legible');

      const tooLong = await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'rejected', rejection_message: 'x'.repeat(1001) })
        .expect(400);
      expect(tooLong.body.error.code).toBe('ADMIN_007');
    });
  });

  describe('Super Admin user management', () => {
    const newAdminEmail = 'created-admin-e2e@e2e-test.local';
    let createdAdminId: string;

    it('creates a new admin', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/users')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          email: newAdminEmail,
          phone: testPhone('0006'),
          full_name: 'Created Admin',
          password: 'AdminPass123',
        })
        .expect(201);
      expect(res.body.data.role).toBe('admin');
      createdAdminId = res.body.data.user_id;
    });

    it('rejects a duplicate email (ADMIN_003)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/users')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          email: newAdminEmail,
          phone: testPhone('0007'),
          full_name: 'Dup Admin',
          password: 'AdminPass123',
        })
        .expect(409);
      expect(res.body.error.code).toBe('ADMIN_003');
    });

    it('lists admins including the newly created one', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/users')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.some((a: { email: string }) => a.email === newAdminEmail)).toBe(true);
    });

    it('blocks self-deactivation (ADMIN_005)', async () => {
      const res = await request(app.getHttpServer())
        .delete(`/v1/admin/users/${superAdminId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('ADMIN_005');
    });

    it('deactivates a regular admin, who can no longer log in', async () => {
      await request(app.getHttpServer())
        .delete(`/v1/admin/users/${createdAdminId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: newAdminEmail, password: 'AdminPass123' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_004');
    });

    it('returns ADMIN_004 activating a nonexistent admin', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/users/00000000-0000-0000-0000-000000000000/activate')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(404);
      expect(res.body.error.code).toBe('ADMIN_004');
    });

    it('reactivates a deactivated admin, who can log in again', async () => {
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/users/${createdAdminId}/activate`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Admin activated' });

      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: newAdminEmail, password: 'AdminPass123' })
        .expect(200);
      expect(login.body.data.access_token).toBeDefined();

      const audit = await db.query(
        `SELECT action FROM audit_logs WHERE target_user_id = $1 AND action = 'admin_activated'`,
        [createdAdminId],
      );
      expect(audit.rows).toHaveLength(1);
    });

    it('blocks self-role-change (ADMIN_012)', async () => {
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/users/${superAdminId}/role`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ role: 'admin' })
        .expect(400);
      expect(res.body.error.code).toBe('ADMIN_012');
    });

    it('rejects an invalid role value (GEN_001)', async () => {
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/users/${createdAdminId}/role`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ role: 'caregiver' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('returns ADMIN_004 changing the role of a nonexistent admin', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/admin/users/00000000-0000-0000-0000-000000000000/role')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ role: 'super_admin' })
        .expect(404);
      expect(res.body.error.code).toBe('ADMIN_004');
    });

    it('promotes an admin to super_admin, who can then access /admin/users themselves', async () => {
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/users/${createdAdminId}/role`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ role: 'super_admin' })
        .expect(200);
      expect(res.body.data).toEqual({ user_id: createdAdminId, role: 'super_admin' });

      const list = await request(app.getHttpServer())
        .get('/v1/admin/users')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(list.body.data.find((a: { user_id: string }) => a.user_id === createdAdminId).role).toBe(
        'super_admin',
      );

      const promotedLogin = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: newAdminEmail, password: 'AdminPass123' })
        .expect(200);
      await request(app.getHttpServer())
        .get('/v1/admin/users')
        .set('Authorization', `Bearer ${promotedLogin.body.data.access_token}`)
        .expect(200);

      const audit = await db.query(
        `SELECT before_value, after_value FROM audit_logs WHERE target_user_id = $1 AND action = 'admin_role_changed'`,
        [createdAdminId],
      );
      expect(audit.rows[0].before_value).toEqual({ role: 'admin' });
      expect(audit.rows[0].after_value).toEqual({ role: 'super_admin' });
    });

    it('demotes a super_admin back to admin when another super_admin remains', async () => {
      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/users/${createdAdminId}/role`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ role: 'admin' })
        .expect(200);
      expect(res.body.data).toEqual({ user_id: createdAdminId, role: 'admin' });
    });
  });

  describe('GET /v1/admin/audit-logs', () => {
    it('blocks a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0008', 'Audit RBAC Subject');
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0008'), code: '1234' })
        .expect(200);
      const res = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs')
        .set('Authorization', `Bearer ${login.body.data.access_token}`)
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
      expect(caregiver.user_id).toBeDefined();
    });

    it('records status_changed with before/after values and returns it filtered by target_user_id and action', async () => {
      const { profile_id: profileId, user_id: targetUserId } = await registerCaregiver(
        '0009',
        'Audit Trail Subject',
      );
      await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/status`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'available' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs')
        .query({ target_user_id: targetUserId, action: 'status_changed' })
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      expect(res.body.data).toHaveLength(1);
      const entry = res.body.data[0];
      expect(entry.action).toBe('status_changed');
      expect(entry.entity_type).toBe('caregiver_profiles');
      expect(entry.user_id).toBe(superAdminId);
      expect(entry.target_user_id).toBe(targetUserId);
      expect(entry.before_value).toEqual({ verification_status: 'pending_call' });
      expect(entry.after_value).toEqual({ verification_status: 'available' });
      expect(entry.created_at).toBeDefined();
      expect(res.body.meta).toEqual({ page: 1, limit: 20, total: 1, totalPages: 1 });
    });

    it('rejects an invalid action filter (GEN_005)', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs')
        .query({ action: 'not_a_real_action' })
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(res.body.error.code).toBe('GEN_005');
    });
  });

  describe('PUT /v1/admin/caregivers/:id (generic edit)', () => {
    it('blocks a caregiver token (AUTH_007)', async () => {
      const { profile_id: profileId } = await registerCaregiver('0010', 'Edit RBAC Subject');
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0010'), code: '1234' })
        .expect(200);
      const res = await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${login.body.data.access_token}`)
        .send({ full_name: 'Hacked Name' })
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('updates only the fields provided, does not touch verification_status, and audit-logs before/after', async () => {
      const { profile_id: profileId, user_id: targetUserId } = await registerCaregiver(
        '0011',
        'Edit Target Subject',
      );

      const res = await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ full_name: 'Renamed By Admin', age: 40 })
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Profile updated' });

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.full_name).toBe('Renamed By Admin');
      expect(detail.body.data.age).toBe(40);
      expect(detail.body.data.verification_status).toBe('pending_call');

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs')
        .query({ target_user_id: targetUserId, action: 'admin_edit_profile' })
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data).toHaveLength(1);
      expect(auditRes.body.data[0].before_value).toEqual({
        full_name: 'Edit Target Subject',
        age: 29,
      });
      expect(auditRes.body.data[0].after_value).toEqual({
        full_name: 'Renamed By Admin',
        age: 40,
      });
    });

    it('rejects an out-of-range age (PROFILE_004)', async () => {
      const { profile_id: profileId } = await registerCaregiver('0012', 'Invalid Age Subject');
      const res = await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ age: 200 })
        .expect(400);
      expect(res.body.error.code).toBe('PROFILE_004');
    });

    it('replaces preferred_cities (multi-select) and audit-logs the before/after set', async () => {
      const { profile_id: profileId, user_id: targetUserId } = await registerCaregiver(
        '0022',
        'Preferred Cities Subject',
      );

      await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ preferred_cities: ['bangalore', 'mumbai'] })
        .expect(200);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.preferred_cities.sort()).toEqual(['bangalore', 'mumbai']);

      const res = await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ preferred_cities: ['pune'] })
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Profile updated' });

      const detail2 = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail2.body.data.preferred_cities).toEqual(['pune']);

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs')
        .query({ target_user_id: targetUserId, action: 'admin_edit_profile' })
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const latest = auditRes.body.data[0];
      expect(latest.before_value).toEqual({ preferred_cities: ['bangalore', 'mumbai'] });
      expect(latest.after_value).toEqual({ preferred_cities: ['pune'] });
    });

    it('rejects an invalid preferred_cities value (GEN_001)', async () => {
      const { profile_id: profileId } = await registerCaregiver('0023', 'Invalid City Subject');
      const res = await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ preferred_cities: ['atlantis'] })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });
  });

  describe('Removed work-type/service-mode/salary assignment endpoints', () => {
    it('work-types, service-modes, and salary endpoints no longer exist (404)', async () => {
      const { profile_id: profileId } = await registerCaregiver('0013', 'Removed Endpoints Subject');

      await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}/work-types`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ work_types: ['companion_care'] })
        .expect(404);

      await request(app.getHttpServer())
        .put(`/v1/admin/caregivers/${profileId}/service-modes`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ service_modes: ['24hrs_live_in'] })
        .expect(404);

      await request(app.getHttpServer())
        .patch(`/v1/admin/caregivers/${profileId}/salary`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ salary: 27000 })
        .expect(404);
    });

    it('caregiver detail no longer includes service_modes/work_types/salary fields', async () => {
      const { profile_id: profileId } = await registerCaregiver('0014', 'No Assignment Fields Subject');
      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.service_modes).toBeUndefined();
      expect(detail.body.data.work_types).toBeUndefined();
      expect(detail.body.data.salary).toBeUndefined();
    });
  });

  describe('POST /v1/admin/caregivers/:id/selfie and /documents', () => {
    it('blocks a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0016', 'Doc Upload RBAC Subject');
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0016'), code: '1234' })
        .expect(200);
      const res = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${caregiver.profile_id}/selfie`)
        .set('Authorization', `Bearer ${login.body.data.access_token}`)
        .attach('file', Buffer.from('x'), 'selfie.jpg')
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });

    it('uploads/replaces a selfie, and the signed URL resolves to the new content', async () => {
      const { profile_id: profileId, user_id: targetUserId } = await registerCaregiver(
        '0017',
        'Doc Upload Subject',
      );

      const first = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/selfie`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .attach('file', Buffer.from('original selfie bytes'), 'selfie.jpg')
        .expect(200);
      expect(first.body.data.file_path).toBe(`caregiver-documents/${profileId}/selfie.jpg`);

      const second = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/selfie`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .attach('file', Buffer.from('replaced by admin'), 'selfie.jpg')
        .expect(200);
      expect(second.body.data.file_path).toBe(`caregiver-documents/${profileId}/selfie.jpg`);
      uploadedStoragePaths.push(`${profileId}/selfie.jpg`);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const content = await fetch(detail.body.data.selfie_photo_url).then((r) => r.text());
      expect(content).toBe('replaced by admin');

      const auditRes = await request(app.getHttpServer())
        .get('/v1/admin/audit-logs')
        .query({ target_user_id: targetUserId, action: 'admin_document_uploaded' })
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(auditRes.body.data).toHaveLength(2);
      expect(auditRes.body.data[0].before_value).toEqual({ document_type: 'selfie', had_file: true });
      expect(auditRes.body.data[1].before_value).toEqual({ document_type: 'selfie', had_file: false });
    });

    it('uploads qualification and aadhaar documents', async () => {
      const { profile_id: profileId } = await registerCaregiver('0018', 'Qual Aadhaar Subject');

      const qual = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/documents`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .field('document_type', 'qualification')
        .attach('file', Buffer.from('admin-uploaded qualification'), 'qualification.pdf')
        .expect(200);
      expect(qual.body.data).toEqual({
        message: 'Document uploaded',
        document_type: 'qualification',
        file_path: `caregiver-documents/${profileId}/qualification.pdf`,
      });

      await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/documents`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('admin-uploaded aadhaar'), 'aadhaar.pdf')
        .expect(200);
      uploadedStoragePaths.push(`${profileId}/qualification.pdf`, `${profileId}/aadhaar.pdf`);

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/caregivers/${profileId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.qualification_document_url).toContain('qualification');
      expect(detail.body.data.aadhaar_document_url).toContain('aadhaar');
    });

    it('rejects a 4th "other" document (UPLOAD_003)', async () => {
      const { profile_id: profileId } = await registerCaregiver('0019', 'Other Docs Subject');
      for (let i = 1; i <= 3; i++) {
        await request(app.getHttpServer())
          .post(`/v1/admin/caregivers/${profileId}/documents`)
          .set('Authorization', `Bearer ${superAdminToken}`)
          .field('document_type', 'other')
          .attach('file', Buffer.from(`other ${i}`), `other${i}.txt`)
          .expect(200);
        uploadedStoragePaths.push(`${profileId}/other_${i}.txt`);
      }
      const res = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/documents`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .field('document_type', 'other')
        .attach('file', Buffer.from('other 4'), 'other4.txt')
        .expect(400);
      expect(res.body.error.code).toBe('UPLOAD_003');
    });

    it('rejects a missing file (UPLOAD_001) and an oversized file (UPLOAD_002)', async () => {
      const { profile_id: profileId } = await registerCaregiver('0020', 'Bad Upload Subject');

      const missing = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/selfie`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(400);
      expect(missing.body.error.code).toBe('UPLOAD_001');

      const bigBuffer = Buffer.alloc(11 * 1024 * 1024);
      const oversized = await request(app.getHttpServer())
        .post(`/v1/admin/caregivers/${profileId}/selfie`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .attach('file', bigBuffer, 'big.jpg')
        .expect(400);
      expect(oversized.body.error.code).toBe('UPLOAD_002');
    });
  });
});
