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
    overrides: { religion?: string; preferred_cities?: string[] } = {},
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
    it('returns the full profile with nulls for unset fields', async () => {
      const res = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);

      expect(res.body.data.user_id).toBe(userId);
      expect(res.body.data.profile_id).toBe(profileId);
      expect(res.body.data.languages).toEqual(['hindi', 'english']);
      expect(res.body.data.selfie_photo_url).toBeNull();
      expect(res.body.data.service_modes).toEqual([]);
      expect(res.body.data.verification_status).toBe('pending_call');
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

  describe('PUT /v1/caregiver/profile/basic', () => {
    it('updates fields without changing verification_status', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/basic')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ age: 30, languages: ['tamil'] })
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
      expect(emailService.sendToAdmin).toHaveBeenCalledWith(
        expect.stringContaining('profile updated'),
        expect.any(String),
      );
    });

    it('rejects an extra/admin-only field like salary (GEN_001, whitelist enforced)', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/basic')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ age: 30, languages: ['hindi'], salary: 50000 })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects full_name — caregivers can no longer self-edit their name (GEN_001, whitelist enforced)', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/basic')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ full_name: 'Hacked Name', age: 30, languages: ['hindi'] })
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
        .put('/v1/caregiver/profile/basic')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ gender: 'other', age: 30, languages: ['hindi'] })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);
      expect(profile.body.data.gender).not.toBe('other');
    });
  });

  describe('Document uploads + advanced details submission', () => {
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

    it('rejects advanced details submission while still pending_call (PROFILE_008)', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
        })
        .expect(403);
      expect(res.body.error.code).toBe('PROFILE_008');
    });

    it('rejects an advanced-details payload that still includes code (GEN_001, whitelist enforced — code is set at registration now)', async () => {
      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          code: '9999',
          terms_accepted: true,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('submits advanced details successfully once call_verified; the registration-time code still logs in', async () => {
      await db.query(
        "UPDATE caregiver_profiles SET verification_status = 'call_verified' WHERE id = $1",
        [profileId],
      );

      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
        })
        .expect(200);

      expect(res.body.data).toEqual({
        message: 'Advanced details submitted',
        verification_status: 'pending_verification',
      });
      expect(emailService.sendToAdmin).toHaveBeenCalledWith(
        expect.stringContaining('Advanced details'),
        expect.any(String),
      );

      const status = await request(app.getHttpServer())
        .get('/v1/caregiver/verification-status')
        .set('Authorization', `Bearer ${accessToken}`)
        .expect(200);
      expect(status.body.data.verification_status).toBe('pending_verification');
      expect(status.body.data.submitted_at).not.toBeNull();

      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '1234' })
        .expect(200);
      expect(login.body.data.advanced_details_completed).toBe(true);
    });

    it('rejects submission when aadhaar is missing (PROFILE_017), but succeeds once only aadhaar is uploaded — qualification stays optional', async () => {
      const created = await registerTestCaregiver('0002');
      const token = created.access_token as string;
      const otherProfileId = created.profile_id as string;

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/selfie')
        .set('Authorization', `Bearer ${token}`)
        .attach('file', Buffer.from('fake selfie bytes'), 'selfie.jpg')
        .expect(200);

      await db.query(
        "UPDATE caregiver_profiles SET verification_status = 'call_verified' WHERE id = $1",
        [otherProfileId],
      );

      const payload = {
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
      };

      const withoutAadhaar = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send(payload)
        .expect(400);
      expect(withoutAadhaar.body.error.code).toBe('PROFILE_017');

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);

      const res = await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send(payload)
        .expect(200);
      expect(res.body.data.verification_status).toBe('pending_verification');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.qualification_document_url).toBeNull();
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

    it('updates the phone and sends an available caregiver back for review; unavailable/pending_call stay as-is otherwise', async () => {
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
      expect(availableRes.body.data.verification_status).toBe('pending_verification');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${available.access_token}`)
        .expect(200);
      expect(profile.body.data.phone).toBe(testPhone('0091'));
      expect(profile.body.data.verification_status).toBe('pending_verification');
    });
  });

  describe('PATCH /v1/caregiver/profile/advanced', () => {
    it('throws PROFILE_025 before advanced details have ever been submitted', async () => {
      const created = await registerTestCaregiver('0010');
      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${created.access_token}`)
        .send({ highest_qualification: 'anm_student_backlog' })
        .expect(403);
      expect(res.body.error.code).toBe('PROFILE_025');
    });

    it('edits a subset of fields post-verification without touching verification_status or other fields', async () => {
      const created = await registerTestCaregiver('0011');
      const token = created.access_token as string;
      const otherProfileId = created.profile_id as string;

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);
      await db.query(
        "UPDATE caregiver_profiles SET verification_status = 'call_verified' WHERE id = $1",
        [otherProfileId],
      );
      await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
        })
        .expect(200);
      // Simulate the caregiver having since been fully verified.
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE id = $1", [
        otherProfileId,
      ]);

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({ highest_qualification: 'anm_student_backlog' })
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Profile updated', has_pending_edits: true });

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.highest_qualification).toBe('anm_student_backlog');
      expect(profile.body.data.religion).toBe('hindu');
      expect(profile.body.data.verification_status).toBe('available');
    });

    it('replaces preferred_cities (multi-select) via a partial edit', async () => {
      const created = await registerTestCaregiver('0015', { preferred_cities: ['bangalore'] });
      const token = created.access_token as string;
      const otherProfileId = created.profile_id as string;

      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);
      await db.query(
        "UPDATE caregiver_profiles SET verification_status = 'call_verified' WHERE id = $1",
        [otherProfileId],
      );
      await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
        })
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({ preferred_cities: ['mumbai', 'pune'] })
        .expect(200);
      expect(res.body.data).toEqual({ message: 'Profile updated', has_pending_edits: true });

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.preferred_cities.sort()).toEqual(['mumbai', 'pune']);
    });

    it('rejects a preferred_cities value outside the enum (GEN_001)', async () => {
      const created = await registerTestCaregiver('0012');
      const token = created.access_token as string;
      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);
      await db.query(
        "UPDATE caregiver_profiles SET verification_status = 'call_verified' WHERE id = $1",
        [created.profile_id],
      );
      await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
        })
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({ preferred_cities: ['atlantis'] })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects religion on self-edit — it is set once at registration and locked thereafter (GEN_001, whitelist enforced)', async () => {
      const created = await registerTestCaregiver('0017');
      const token = created.access_token as string;
      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);
      await db.query(
        "UPDATE caregiver_profiles SET verification_status = 'call_verified' WHERE id = $1",
        [created.profile_id],
      );
      await request(app.getHttpServer())
        .put('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({
          highest_qualification: 'rn_above_2_years',
          terms_accepted: true,
        })
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch('/v1/caregiver/profile/advanced')
        .set('Authorization', `Bearer ${token}`)
        .send({ religion: 'muslim' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');

      const profile = await request(app.getHttpServer())
        .get('/v1/caregiver/profile')
        .set('Authorization', `Bearer ${token}`)
        .expect(200);
      expect(profile.body.data.religion).toBe('hindu');
    });
  });

  describe('Aadhaar re-upload review trigger', () => {
    it('re-uploading aadhaar on an available profile sends it back for pending_verification', async () => {
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
      expect(profile.body.data.verification_status).toBe('pending_verification');
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
});
