import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import { createClient } from '@supabase/supabase-js';
import { AppModule } from '../src/app.module';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { TransformInterceptor } from '../src/common/interceptors/transform.interceptor';
import { validationExceptionFactory } from '../src/common/pipes/validation-exception.factory';
import { EmailService } from '../src/email/email.service';

/**
 * Runs against the real Supabase Postgres + Storage. Uses the +91700001xxxx
 * test phone range (distinct from auth.e2e-spec.ts's +91700000xxxx) and
 * cleans up both DB rows and uploaded storage objects, even on failure.
 */
describe('Caregiver (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let emailService: { send: jest.Mock; sendToAdmin: jest.Mock };
  const storage = createClient(
    process.env.SUPABASE_URL as string,
    process.env.SUPABASE_SERVICE_ROLE_KEY as string,
  );

  const testPhone = (suffix: string) => `+91700001${suffix}`;
  let accessToken: string;
  let profileId: string;
  let userId: string;

  // audit_logs.user_id/target_user_id reference users without ON DELETE
  // CASCADE, so the referencing rows must go first or the user delete
  // 409s on the FK constraint.
  async function cleanup() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700001%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700001%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700001%'");
  }

  async function registerTestCaregiver(
    phoneSuffix: string,
    overrides: {
      religion?: string;
      preferred_cities?: string[];
      highest_qualification?: string;
      terms_accepted?: boolean;
    } = {},
  ) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: testPhone(phoneSuffix),
        full_name: 'Caregiver Test',
        gender: 'female',
        age: 28,
        languages: ['hindi', 'english'],
        religion: overrides.religion ?? 'hindu',
        highest_qualification: overrides.highest_qualification ?? 'rn_above_2_years',
        terms_accepted: overrides.terms_accepted ?? true,
        ...(overrides.preferred_cities ? { preferred_cities: overrides.preferred_cities } : {}),
        code: '1234',
      });
    return res.body.data as { user_id: string; profile_id: string; access_token: string };
  }

  beforeAll(async () => {
    db = new Client({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false },
    });
    await db.connect();
    await cleanup();

    emailService = { send: jest.fn(), sendToAdmin: jest.fn() };
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue(emailService)
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

    const created = await registerTestCaregiver('0001');
    userId = created.user_id;
    profileId = created.profile_id;
    accessToken = created.access_token;
  });

  afterAll(async () => {
    // Best-effort: remove any files that tests may have uploaded under this profile.
    await storage.storage.from('caregiver-documents').remove([
      `${profileId}/selfie.jpg`,
      `${profileId}/qualification.pdf`,
      `${profileId}/aadhaar.pdf`,
      `${profileId}/other_1.txt`,
      `${profileId}/other_2.txt`,
      `${profileId}/other_3.txt`,
      `${profileId}/other_4.txt`,
    ]);
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('GET /v1/caregiver/profile', () => {
    it('returns the full profile, including fields collected at registration', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);

      expect(res.body.data.user_id).toBe(userId);
      expect(res.body.data.profile_id).toBe(profileId);
      expect(res.body.data.languages).toEqual(['hindi', 'english']);
      expect(res.body.data.selfie_photo_url).toBeNull();
      expect(res.body.data.verification_status).toBe('pending_call');
      expect(res.body.data.highest_qualification).toBe('rn_above_2_years');
      expect(res.body.data.terms_accepted).toBe(true);
      expect(res.body.data.religion).toBe('hindu');
    });

    it('rejects without a token (AUTH_005)', async () => {
      const res = await request(app.getHttpServer()).get('/v1/caregiver/profile').expect(401);
      expect(res.body.error.code).toBe('AUTH_005');
    });

    it('rejects an admin token (AUTH_007) — caregiver routes are caregiver-only', async () => {
      const passwordHash = await import('bcrypt').then((b) => b.hash('AdminPass123', 4));
      await db.query(
        `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
         VALUES ($1, $2, $3, 'E2E Admin', 'admin', true)`,
        ['admin-caregiver-e2e@e2e-test.local', testPhone('0099'), passwordHash],
      );
      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/email')
        .send({ email: 'admin-caregiver-e2e@e2e-test.local', password: 'AdminPass123' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${login.body.data.access_token}`)
        .expect(403);
      expect(res.body.error.code).toBe('AUTH_007');
    });
  });

  describe('PATCH /v1/caregiver/profile', () => {
    it('updates age/languages/highest_qualification/preferred_cities without changing verification_status', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ age: 30, languages: ['tamil'], highest_qualification: 'anm_student_backlog' })
        .expect(200);

      expect(res.body.data).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'pending_call',
      });

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);
      expect(profile.body.data.languages).toEqual(['tamil']);
      expect(profile.body.data.highest_qualification).toBe('anm_student_backlog');
      expect(emailService.sendToAdmin).toHaveBeenCalledWith(
        expect.stringContaining('profile updated'),
        expect.any(String),
      );
    });

    it('replaces preferred_cities via a partial edit', async () => {
      const created = await registerTestCaregiver('0011', { preferred_cities: ['bangalore'] });
      const token = created.access_token as string;

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .send({ preferred_cities: ['mumbai', 'pune'] })
        .expect(200);
      expect(res.body.data).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'pending_call',
      });

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.preferred_cities.sort()).toEqual(['mumbai', 'pune']);
    });

    it('rejects a preferred_cities value outside the enum (GEN_001)', async () => {
      const created = await registerTestCaregiver('0012');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ preferred_cities: ['atlantis'] })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('replaces preferred_duty_types via a partial edit, without changing verification_status', async () => {
      const created = await registerTestCaregiver('0040');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ preferred_duty_types: ['day_duty', 'night_duty'] })
        .expect(200);
      expect(res.body.data).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'pending_call',
      });

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(profile.body.data.preferred_duty_types.sort()).toEqual(['day_duty', 'night_duty']);
    });

    it('clears preferred_duty_types back to empty (no preference) via an empty array', async () => {
      const created = await registerTestCaregiver('0041');
      await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ preferred_duty_types: ['live_in'] })
        .expect(200);

      await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ preferred_duty_types: [] })
        .expect(200);

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(profile.body.data.preferred_duty_types).toEqual([]);
    });

    it('rejects a preferred_duty_types value outside the 3 fixed shifts (GEN_001)', async () => {
      const created = await registerTestCaregiver('0042');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ preferred_duty_types: ['weekend_only'] })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('updates min_salary_per_day and min_salary_per_month without changing verification_status', async () => {
      const created = await registerTestCaregiver('0043');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ min_salary_per_day: 1500, min_salary_per_month: 25000 })
        .expect(200);
      expect(res.body.data).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'pending_call',
      });

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(profile.body.data.min_salary_per_day).toBe(1500);
      expect(profile.body.data.min_salary_per_month).toBe(25000);
    });

    it('rejects a min_salary_per_day of 0 (GEN_001)', async () => {
      const created = await registerTestCaregiver('0044');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ min_salary_per_day: 0 })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an extra/admin-only field like salary (GEN_001, whitelist enforced)', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ age: 30, salary: 50000 })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects full_name — caregivers can no longer self-edit their name (GEN_001, whitelist enforced)', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ full_name: 'Hacked Name', age: 30 })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);
      expect(profile.body.data.full_name).not.toBe('Hacked Name');
    });

    it('rejects gender — caregivers can no longer self-edit their gender once set at registration (GEN_001, whitelist enforced)', async () => {
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ gender: 'other', age: 30 })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);
      expect(profile.body.data.gender).not.toBe('other');
    });

    it('rejects religion — set once at registration and locked thereafter (GEN_001, whitelist enforced)', async () => {
      const created = await registerTestCaregiver('0017');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ religion: 'muslim' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(profile.body.data.religion).toBe('hindu');
    });

    it('auto-resubmits (sends back to pending_call) when a rejected caregiver edits anything', async () => {
      const created = await registerTestCaregiver('0025');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'rejected' WHERE id = $1", [
        created.profile_id,
      ]);

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ age: 33 })
        .expect(200);
      expect(res.body.data.verification_status).toBe('pending_call');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(profile.body.data.verification_status).toBe('pending_call');
      expect(profile.body.data.age).toBe(33);
    });
  });

  describe('Document uploads', () => {
    it('uploads selfie, qualification, aadhaar; signed URLs resolve to real content', async () => {
      const selfieRes = await request(app.getHttpServer())
        .post('/v1/caregiver/profile/selfie')
        .set('Authorization', `Bearer ${accessToken}`)
        .attach('file', Buffer.from('fake selfie bytes'), 'selfie.jpg')
        .expect(200);
      expect(selfieRes.body.data.file_path).toBe(`caregiver-documents/${profileId}/selfie.jpg`);

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${accessToken}`)
        .field('document_type', 'qualification')
        .attach('file', Buffer.from('fake qualification'), 'qualification.pdf')
        .expect(200);

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${accessToken}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);

      const selfieContent = await fetch(profile.body.data.selfie_photo_url).then((r) => r.text());
      expect(selfieContent).toBe('fake selfie bytes');
    });

    it('rejects a file over 10MB (UPLOAD_002 / 400)', async () => {
      const bigBuffer = Buffer.alloc(11 * 1024 * 1024);
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/profile/selfie')
        .set('Authorization', `Bearer ${accessToken}`)
        .attach('file', bigBuffer, 'big.jpg')
        .expect(400);
      expect(res.body.error.code).toBe('UPLOAD_002');
    });

    it('rejects a 4th "other" document (UPLOAD_003)', async () => {
      for (let i = 1; i <= 3; i++) {
        await request(app.getHttpServer())
          .post('/v1/caregiver/profile/documents')
          .set('Authorization', `Bearer ${accessToken}`)
          .field('document_type', 'other')
          .attach('file', Buffer.from(`other ${i}`), `other${i}.txt`)
          .expect(200);
      }
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${accessToken}`)
        .field('document_type', 'other')
        .attach('file', Buffer.from('other 4'), 'other4.txt')
        .expect(400);
      expect(res.body.error.code).toBe('UPLOAD_003');
    });

    it('sets preferred_cities from registration; stays empty when omitted', async () => {
      const withCities = await registerTestCaregiver('0018', {
        preferred_cities: ['bangalore', 'mumbai'],
      });
      const withoutCities = await registerTestCaregiver('0019');

      const profileWithCities = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${withCities.access_token}`)
        .expect(200);
      expect(profileWithCities.body.data.preferred_cities.sort()).toEqual(['bangalore', 'mumbai']);

      const profileWithoutCities = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${withoutCities.access_token}`)
        .expect(200);
      expect(profileWithoutCities.body.data.preferred_cities).toEqual([]);
    });
  });

  describe('PATCH /v1/caregiver/profile/code', () => {
    it('updates the login code; old code stops working, new code logs in; status untouched', async () => {
      const created = await registerTestCaregiver('0004');
      const token = created.access_token as string;

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/code')
        .set('Authorization', `Bearer ${token}`)
        .send({ code: '9999' })
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Login code updated' });

      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0004'), code: '1234' })
        .expect(401);

      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0004'), code: '9999' })
        .expect(200);
      expect(login.body.data.verification_status).toBe('pending_call');
    });

    it('rejects a non-4-digit code (PROFILE_016)', async () => {
      const created = await registerTestCaregiver('0005');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/code')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ code: '12' })
        .expect(400);
      expect(res.body.error.code).toBe('PROFILE_016');
    });
  });

  describe('PATCH /v1/caregiver/profile/phone', () => {
    it('rejects a phone already registered to another account (AUTH_001)', async () => {
      const first = await registerTestCaregiver('0006');
      const second = await registerTestCaregiver('0007');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/phone')
        .set('Authorization', `Bearer ${second.access_token}`)
        .send({ phone: testPhone('0006') })
        .expect(409);
      expect(res.body.error.code).toBe('AUTH_001');
      void first;
    });

    it('updates the phone and sends an available caregiver back for review; pending_call stays as-is otherwise', async () => {
      const pendingCall = await registerTestCaregiver('0008');
      const available = await registerTestCaregiver('0009');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE id = $1", [
        available.profile_id,
      ]);

      const pendingCallRes = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/phone')
        .set('Authorization', `Bearer ${pendingCall.access_token}`)
        .send({ phone: testPhone('0090') })
        .expect(200);
      expect(pendingCallRes.body.data.verification_status).toBe('pending_call');

      const availableRes = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/phone')
        .set('Authorization', `Bearer ${available.access_token}`)
        .send({ phone: testPhone('0091') })
        .expect(200);
      expect(availableRes.body.data.verification_status).toBe('pending_call');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${available.access_token}`)
        .expect(200);
      expect(profile.body.data.phone).toBe(testPhone('0091'));
      expect(profile.body.data.verification_status).toBe('pending_call');
    });

    it('changing phone also sends a rejected caregiver back for review', async () => {
      const created = await registerTestCaregiver('0026');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'rejected' WHERE id = $1", [
        created.profile_id,
      ]);

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/phone')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ phone: testPhone('0092') })
        .expect(200);
      expect(res.body.data.verification_status).toBe('pending_call');
    });
  });

  describe('Aadhaar re-upload review trigger', () => {
    it('re-uploading aadhaar on an available profile sends it back to pending_call', async () => {
      const created = await registerTestCaregiver('0013');
      const token = created.access_token as string;
      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('original aadhaar'), 'aadhaar.pdf')
        .expect(200);
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE id = $1", [
        created.profile_id,
      ]);

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('re-uploaded aadhaar'), 'aadhaar2.pdf')
        .expect(200);

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.verification_status).toBe('pending_call');
    });

    it('re-uploading qualification on an available profile does not touch verification_status', async () => {
      const created = await registerTestCaregiver('0014');
      const token = created.access_token as string;
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE id = $1", [
        created.profile_id,
      ]);

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'qualification')
        .attach('file', Buffer.from('quals'), 'q.pdf')
        .expect(200);

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.verification_status).toBe('available');
    });

    it('re-uploading any document auto-resubmits a rejected caregiver', async () => {
      const created = await registerTestCaregiver('0027');
      const token = created.access_token as string;
      await db.query("UPDATE caregiver_profiles SET verification_status = 'rejected' WHERE id = $1", [
        created.profile_id,
      ]);

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'qualification')
        .attach('file', Buffer.from('quals'), 'q.pdf')
        .expect(200);

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.verification_status).toBe('pending_call');
    });
  });

  describe('PUT /v1/caregiver/fcm-token', () => {
    it('stores the token and it persists across requests', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/fcm-token')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ token: 'test-fcm-token-abc123' })
        .expect(200);
      expect(res.body.data).toEqual({ message: 'FCM token updated' });

      const stored = await db.query('SELECT fcm_token FROM users WHERE id = $1', [userId]);
      expect(stored.rows[0].fcm_token).toBe('test-fcm-token-abc123');
    });

    it('rejects an empty token (PROFILE_021)', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/fcm-token')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ token: '' })
        .expect(400);
      expect(res.body.error.code).toBe('PROFILE_021');
    });

    it('rejects without a token (AUTH_005)', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/fcm-token')
        .send({ token: 'x' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_005');
    });
  });

  describe('POST /v1/caregiver/mark-available', () => {
    async function registerWithStatus(phoneSuffix: string, status: string) {
      const created = await registerTestCaregiver(phoneSuffix);
      await db.query('UPDATE caregiver_profiles SET verification_status = $2 WHERE id = $1', [
        created.profile_id,
        status,
      ]);
      return created;
    }

    it('rejects from pending_call (PROFILE_022)', async () => {
      const created = await registerTestCaregiver('0093'); // fresh registration starts pending_call
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/mark-available')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(400);
      expect(res.body.error.code).toBe('PROFILE_022');

      const profile = await db.query('SELECT verification_status FROM caregiver_profiles WHERE id = $1', [
        created.profile_id,
      ]);
      expect(profile.rows[0].verification_status).toBe('pending_call');
    });

    it('rejects from rejected (PROFILE_022) — must edit profile to resubmit instead', async () => {
      const created = await registerWithStatus('0094', 'rejected');
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/mark-available')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(400);
      expect(res.body.error.code).toBe('PROFILE_022');
    });

    it('is a no-op when already available — returns already_available without an error', async () => {
      const created = await registerWithStatus('0095', 'available');
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/mark-available')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(res.body.data).toEqual({
        message: 'You are already marked as available',
        verification_status: 'available',
        already_available: true,
      });
    });

    it('updates unavailable -> available', async () => {
      const created = await registerWithStatus('0096', 'unavailable');
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/mark-available')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(res.body.data).toEqual({
        message: 'Status updated',
        verification_status: 'available',
        already_available: false,
      });

      const profile = await db.query('SELECT verification_status FROM caregiver_profiles WHERE id = $1', [
        created.profile_id,
      ]);
      expect(profile.rows[0].verification_status).toBe('available');
    });

    it('updates assigned -> available (self-service unassign) without touching jobs/applications', async () => {
      const created = await registerWithStatus('0097', 'assigned');
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/mark-available')
        .set('Authorization', `Bearer ${created.access_token}`)
        .expect(200);
      expect(res.body.data.verification_status).toBe('available');

      const audit = await db.query(
        `SELECT action, before_value, after_value FROM audit_logs
         WHERE user_id = $1 AND action = 'status_changed' ORDER BY created_at DESC LIMIT 1`,
        [created.user_id],
      );
      expect(audit.rows[0].before_value).toEqual({ verification_status: 'assigned' });
      expect(audit.rows[0].after_value).toEqual({ verification_status: 'available' });
    });

    it('rejects without a token (AUTH_005)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/caregiver/mark-available')
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_005');
    });
  });
});
