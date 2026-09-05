import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import { AppModule } from '../src/app.module';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { TransformInterceptor } from '../src/common/interceptors/transform.interceptor';
import { validationExceptionFactory } from '../src/common/pipes/validation-exception.factory';
import { EmailService } from '../src/email/email.service';
import { FcmService } from '../src/fcm/fcm.service';

/**
 * Runs against the real Supabase Postgres. Uses the +91700012xxxx test
 * phone range (distinct from every other e2e suite, including
 * organisation.e2e-spec.ts's own +91700004 range). Covers the batch of
 * NurseNow Organisation enhancements added on top of the already-tested
 * base flow: Agency org type, optional Area, type_of_nurse "Others" free
 * text, Number of Vacancies, Preferred Gender (+ caregiver-side
 * enforcement), and the new org self-edit/self-cancel endpoints.
 */
describe('Organisation requirement enhancements (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let fcmService: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };

  const testPhone = (suffix: string) => `+91700012${suffix}`;
  const caregiverPhone = (suffix: string) => `+91700012${suffix}`;

  async function cleanup() {
    await db.query(
      `DELETE FROM organisation_requirement_applications WHERE requirement_id IN (
         SELECT id FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700012%')
       )`,
    );
    await db.query(
      `DELETE FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700012%')`,
    );
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700012%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700012%')`,
    );
    await db.query(
      "DELETE FROM organisation_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700012%')",
    );
    // caregiver_profiles.verified_by can point at a DIFFERENT test user in
    // this same prefix (the org whose "Accept Anyway"/undo-accept flow set
    // it) — must be deleted before the bulk `users` delete below, or that
    // other user's row can't be removed (FK violation on
    // caregiver_profiles_verified_by_fkey). Mirrors organisation.e2e-spec.ts.
    await db.query(
      "DELETE FROM caregiver_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700012%')",
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700012%'");
  }

  async function registerOrganisation(
    phoneSuffix: string,
    overrides: Record<string, unknown> = {},
  ) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/organisation')
      .send({
        phone: testPhone(phoneSuffix),
        code: '1234',
        organisation_name: 'Enhancements Test Org',
        contact_person_name: 'Test Contact',
        organisation_type: 'hospital',
        city: 'bangalore',
        area: 'Indiranagar',
        terms_accepted: true,
        ...overrides,
      })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  async function registerCaregiver(phoneSuffix: string, gender: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: caregiverPhone(phoneSuffix),
        full_name: 'Enhancements Test Caregiver',
        gender,
        age: 28,
        languages: ['hindi'],
        religion: 'hindu',
        highest_qualification: 'rn_above_2_years',
        terms_accepted: true,
        code: '1234',
      })
      .expect(201);
    return res.body.data as { user_id: string; profile_id: string; access_token: string };
  }

  const requirementPayload = (overrides: Record<string, unknown> = {}) => ({
    type_of_nurse: 'registered_nurse',
    accommodation_provided: true,
    food_provided: false,
    duration_type: 'short_term',
    ...overrides,
  });

  // PATCH /organisation/requirements/:id (org self-edit) requires
  // number_of_vacancies, unlike POST .../requirements (org-owned but
  // optional-with-a-default there) — see UpdateMyOrganisationRequirementDto.
  const selfEditPayload = (overrides: Record<string, unknown> = {}) => ({
    ...requirementPayload(),
    number_of_vacancies: 1,
    ...overrides,
  });

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanup();

    fcmService = { sendToUser: jest.fn(), sendToAllCaregivers: jest.fn() };
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
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('POST /v1/auth/register/organisation — Agency type + optional Area', () => {
    it('accepts organisation_type=agency', async () => {
      const org = await registerOrganisation('0001', { organisation_type: 'agency' });
      const res = await request(app.getHttpServer())
        .get('/v1/organisation/me')
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(res.body.data.organisation_name).toBe('Enhancements Test Org');
    });

    it('rejects an unrecognized organisation_type', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register/organisation')
        .send({
          phone: testPhone('0002'),
          code: '1234',
          organisation_name: 'Bad Type Org',
          contact_person_name: 'Someone',
          organisation_type: 'pharmacy',
          city: 'bangalore',
          area: 'Indiranagar',
          terms_accepted: true,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('registers successfully with area omitted entirely', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register/organisation')
        .send({
          phone: testPhone('0003'),
          code: '1234',
          organisation_name: 'No Area Org',
          contact_person_name: 'Someone',
          organisation_type: 'clinic',
          city: 'bangalore',
          terms_accepted: true,
        })
        .expect(201);
      expect(res.body.data.access_token).toBeDefined();

      const row = await db.query('SELECT area FROM organisation_profiles WHERE user_id = $1', [
        res.body.data.user_id,
      ]);
      expect(row.rows[0].area).toBeNull();
    });
  });

  describe('POST /v1/organisation/requirements — Type of Nurse "Others" free text', () => {
    it('rejects type_of_nurse=others with no type_of_nurse_other', async () => {
      const org = await registerOrganisation('0010');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ type_of_nurse: 'others' }))
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects type_of_nurse=others with a blank type_of_nurse_other', async () => {
      const org = await registerOrganisation('0011');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ type_of_nurse: 'others', type_of_nurse_other: '   ' }))
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('accepts type_of_nurse=others with a non-blank type_of_nurse_other, and persists it', async () => {
      const org = await registerOrganisation('0012');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ type_of_nurse: 'others', type_of_nurse_other: 'Physiotherapist' }))
        .expect(201);
      expect(res.body.data.type_of_nurse_other).toBe('Physiotherapist');
    });

    it('nulls type_of_nurse_other server-side when type_of_nurse is not others, even if sent', async () => {
      const org = await registerOrganisation('0013');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(
          requirementPayload({
            type_of_nurse: 'registered_nurse',
            type_of_nurse_other: 'should be ignored',
          }),
        )
        .expect(201);
      expect(res.body.data.type_of_nurse_other).toBeNull();
    });
  });

  describe('POST /v1/organisation/requirements — Number of Vacancies', () => {
    it('defaults to 1 when omitted', async () => {
      const org = await registerOrganisation('0020');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      expect(res.body.data.number_of_vacancies).toBe(1);
    });

    it.each([
      ['0031', 0],
      ['0032', -1],
      ['0033', 50],
      ['0034', 100],
    ])('rejects %s (must be > 0 and < 50): %d', async (phoneSuffix, value) => {
      const org = await registerOrganisation(phoneSuffix);
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ number_of_vacancies: value }))
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('accepts and persists a value within range', async () => {
      const org = await registerOrganisation('0040');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ number_of_vacancies: 12 }))
        .expect(201);
      expect(res.body.data.number_of_vacancies).toBe(12);
    });
  });

  describe('POST /v1/organisation/requirements — Preferred Gender', () => {
    it('rejects other as a preference (only male/female are offered)', async () => {
      const org = await registerOrganisation('0050');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ preferred_gender: 'other' }))
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('omitted = no preference (null)', async () => {
      const org = await registerOrganisation('0051');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      expect(res.body.data.preferred_gender).toBeNull();
    });
  });

  describe('POST /v1/organisation/requirements — Duration Type', () => {
    it('is mandatory — rejects when omitted', async () => {
      const org = await registerOrganisation('0090');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ type_of_nurse: 'registered_nurse', accommodation_provided: true, food_provided: false })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an unrecognized value', async () => {
      const org = await registerOrganisation('0091');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ duration_type: 'medium_term' }))
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it.each([
      ['0092', 'short_term'],
      ['0093', 'long_term'],
    ])('accepts and persists %s: %s', async (phoneSuffix, value) => {
      const org = await registerOrganisation(phoneSuffix);
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ duration_type: value }))
        .expect(201);
      expect(res.body.data.duration_type).toBe(value);
    });

    it('can be changed via org self-edit', async () => {
      const org = await registerOrganisation('0094');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ duration_type: 'short_term' }))
        .expect(201);
      const requirementId = create.body.data.id;

      const res = await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(selfEditPayload({ duration_type: 'long_term' }))
        .expect(200);
      expect(res.body.data.duration_type).toBe('long_term');
    });
  });

  describe('Caregiver-facing preferred_gender enforcement', () => {
    it('a female-preferred requirement is hidden from a male caregiver and visible to a female one', async () => {
      const org = await registerOrganisation('0060');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ preferred_gender: 'female' }))
        .expect(201);
      const requirementId = create.body.data.id;

      // Approve it directly via SQL (mirroring what PATCH
      // /admin/organisation-requirements/:id would persist) so it's
      // active/visible without needing a throwaway admin account just for
      // this check.
      await db.query(
        `UPDATE organisation_requirements SET status = 'active', posted_at = NOW() WHERE id = $1`,
        [requirementId],
      );

      const maleCaregiver = await registerCaregiver('0161', 'male');
      const femaleCaregiver = await registerCaregiver('0162', 'female');

      const maleList = await request(app.getHttpServer())
        .get('/v1/caregiver/organisation-requirements')
        .set('Authorization', `Bearer ${maleCaregiver.access_token}`)
        .expect(200);
      expect(maleList.body.data.some((r: { id: string }) => r.id === requirementId)).toBe(false);

      const femaleList = await request(app.getHttpServer())
        .get('/v1/caregiver/organisation-requirements')
        .set('Authorization', `Bearer ${femaleCaregiver.access_token}`)
        .expect(200);
      expect(femaleList.body.data.some((r: { id: string }) => r.id === requirementId)).toBe(true);
    });
  });

  describe('PATCH /v1/organisation/requirements/:id — org self-edit', () => {
    it('updates org-owned fields without touching status/admin-set fields', async () => {
      const org = await registerOrganisation('0070');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ number_of_vacancies: 2 }))
        .expect(201);
      const requirementId = create.body.data.id;

      const res = await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(
          requirementPayload({
            type_of_nurse: 'others',
            type_of_nurse_other: 'Wound care specialist',
            number_of_vacancies: 7,
            preferred_gender: 'male',
          }),
        )
        .expect(200);

      expect(res.body.data.type_of_nurse).toBe('others');
      expect(res.body.data.type_of_nurse_other).toBe('Wound care specialist');
      expect(res.body.data.number_of_vacancies).toBe(7);
      expect(res.body.data.preferred_gender).toBe('male');
      expect(res.body.data.status).toBe('pending_review');
    });

    it('rejects editing a requirement owned by a different organisation (GEN_002)', async () => {
      const orgA = await registerOrganisation('0071');
      const orgB = await registerOrganisation('0072');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${orgA.access_token}`)
        .send(requirementPayload())
        .expect(201);

      const res = await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${create.body.data.id}`)
        .set('Authorization', `Bearer ${orgB.access_token}`)
        .send(selfEditPayload())
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('rejects editing (JOB_014) once a caregiver has an active application', async () => {
      const org = await registerOrganisation('0073');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = create.body.data.id;
      await db.query(`UPDATE organisation_requirements SET status = 'active', posted_at = NOW() WHERE id = $1`, [
        requirementId,
      ]);

      const caregiver = await registerCaregiver('0174', 'female');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(selfEditPayload())
        .expect(400);
      expect(res.body.error.code).toBe('JOB_014');
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer())
        .patch('/v1/organisation/requirements/00000000-0000-0000-0000-000000000000')
        .send(requirementPayload())
        .expect(401);
    });
  });

  describe('POST /v1/organisation/requirements/:id/cancel — org self-cancel', () => {
    it('cancels the requirement without touching any application — candidates stay visible and actionable', async () => {
      const org = await registerOrganisation('0080');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = create.body.data.id;
      await db.query(`UPDATE organisation_requirements SET status = 'active', posted_at = NOW() WHERE id = $1`, [
        requirementId,
      ]);

      const caregiver = await registerCaregiver('0181', 'female');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const cancelRes = await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${requirementId}/cancel`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(cancelRes.body.data.status).toBe('closed');

      const row = await db.query('SELECT status, cancelled_at FROM organisation_requirements WHERE id = $1', [
        requirementId,
      ]);
      expect(row.rows[0].status).toBe('closed');
      expect(row.rows[0].cancelled_at).not.toBeNull();

      // The candidate's application is untouched — still 'applied', not
      // rejected — and stays fully visible/actionable after cancellation.
      const applicationsRes = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${requirementId}/applications`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(applicationsRes.body.data).toHaveLength(1);
      expect(applicationsRes.body.data[0].status).toBe('applied');
      expect(applicationsRes.body.data[0].phone).toBeDefined();

      const profileRes = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${requirementId}/applications/${applicationsRes.body.data[0].id}/profile`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(profileRes.body.data.full_name).toBeDefined();

      // Still accept/reject-able after cancellation — rejecting requires a
      // reason (JOB_012), same as Individual's own flow.
      const applicationId = applicationsRes.body.data[0].id;
      await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ status: 'rejected' })
        .expect(400)
        .then((res) => expect(res.body.error.code).toBe('JOB_012'));
      await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ status: 'rejected', reason: 'Went with another candidate' })
        .expect(200);

      // Even though the requirement is cancelled AND the candidate was
      // rejected, the organisation can still reselect ("Accept Anyway")
      // them — cancellation and rejection never block reconsidering.
      const acceptAnyway = await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);
      expect(acceptAnyway.body.data.status).toBe('accepted');

      const caregiverProfile = await db.query(
        'SELECT verification_status FROM caregiver_profiles WHERE user_id = $1',
        [caregiver.user_id],
      );
      expect(caregiverProfile.rows[0].verification_status).toBe('assigned');
    });

    it('rejects cancelling a second time (JOB_015)', async () => {
      const org = await registerOrganisation('0082');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = create.body.data.id;

      await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${requirementId}/cancel`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${requirementId}/cancel`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(400);
      expect(res.body.error.code).toBe('JOB_015');
    });

    it('rejects cancelling a requirement owned by a different organisation (GEN_002)', async () => {
      const orgA = await registerOrganisation('0083');
      const orgB = await registerOrganisation('0084');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${orgA.access_token}`)
        .send(requirementPayload())
        .expect(201);

      const res = await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${create.body.data.id}/cancel`)
        .set('Authorization', `Bearer ${orgB.access_token}`)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });
  });

  describe('POST /v1/organisation/requirements/:id/reactivate — org self-reactivate', () => {
    it('rejects reactivating a requirement that was never cancelled (JOB_017)', async () => {
      const org = await registerOrganisation('0095');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);

      const res = await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${create.body.data.id}/reactivate`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(400);
      expect(res.body.error.code).toBe('JOB_017');
    });

    it('rejects reactivating a requirement owned by a different organisation (GEN_002)', async () => {
      const orgA = await registerOrganisation('0096');
      const orgB = await registerOrganisation('0097');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${orgA.access_token}`)
        .send(requirementPayload())
        .expect(201);
      await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${create.body.data.id}/cancel`)
        .set('Authorization', `Bearer ${orgA.access_token}`)
        .expect(200);

      const res = await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${create.body.data.id}/reactivate`)
        .set('Authorization', `Bearer ${orgB.access_token}`)
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('reactivates a cancelled requirement back to active, clearing the Cancelled state, without admin re-review',
      async () => {
        const org = await registerOrganisation('0098');
        const create = await request(app.getHttpServer())
          .post('/v1/organisation/requirements')
          .set('Authorization', `Bearer ${org.access_token}`)
          .send(requirementPayload())
          .expect(201);
        const requirementId = create.body.data.id;
        await db.query(`UPDATE organisation_requirements SET status = 'active', posted_at = NOW() WHERE id = $1`, [
          requirementId,
        ]);

        await request(app.getHttpServer())
          .post(`/v1/organisation/requirements/${requirementId}/cancel`)
          .set('Authorization', `Bearer ${org.access_token}`)
          .expect(200);
        const cancelledRow = await db.query(
          'SELECT status, cancelled_at FROM organisation_requirements WHERE id = $1',
          [requirementId],
        );
        expect(cancelledRow.rows[0].status).toBe('closed');
        expect(cancelledRow.rows[0].cancelled_at).not.toBeNull();

        const reactivated = await request(app.getHttpServer())
          .post(`/v1/organisation/requirements/${requirementId}/reactivate`)
          .set('Authorization', `Bearer ${org.access_token}`)
          .expect(200);
        expect(reactivated.body.data.status).toBe('active');

        const row = await db.query('SELECT status, cancelled_at FROM organisation_requirements WHERE id = $1', [
          requirementId,
        ]);
        expect(row.rows[0].status).toBe('active');
        expect(row.rows[0].cancelled_at).toBeNull();

        // Now visible to caregivers again, same as a brand-new posting.
        const caregiver = await registerCaregiver('0195', 'female');
        await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
          caregiver.user_id,
        ]);
        const list = await request(app.getHttpServer())
          .get('/v1/caregiver/organisation-requirements')
          .set('Authorization', `Bearer ${caregiver.access_token}`)
          .expect(200);
        expect(list.body.data.some((r: { id: string }) => r.id === requirementId)).toBe(true);
      });

    it('rejects reactivating while the account is job-posting-blocked (JOB_010)', async () => {
      const org = await registerOrganisation('0099');
      const create = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = create.body.data.id;
      await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${requirementId}/cancel`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);

      await db.query('UPDATE organisation_profiles SET is_job_posting_blocked = true WHERE user_id = $1', [
        org.user_id,
      ]);

      const res = await request(app.getHttpServer())
        .post(`/v1/organisation/requirements/${requirementId}/reactivate`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(403);
      expect(res.body.error.code).toBe('JOB_010');
    });
  });

  describe('PATCH /v1/organisation/profile — org self-edit of every profile field', () => {
    it('updates every provided field, keeping users.full_name and organisation_profiles.contact_person_name '
      + 'in sync', async () => {
        const org = await registerOrganisation('0100');

        await request(app.getHttpServer())
          .patch('/v1/organisation/profile')
          .set('Authorization', `Bearer ${org.access_token}`)
          .send({
            full_name: 'New Contact Person',
            organisation_name: 'New Organisation Name',
            organisation_type: 'clinic',
            city: 'mumbai',
            area: 'Andheri',
          })
          .expect(200);

        const me = await request(app.getHttpServer())
          .get('/v1/organisation/me')
          .set('Authorization', `Bearer ${org.access_token}`)
          .expect(200);
        expect(me.body.data.contact_person_name).toBe('New Contact Person');
        expect(me.body.data.organisation_name).toBe('New Organisation Name');
        expect(me.body.data.organisation_type).toBe('clinic');
        expect(me.body.data.city).toBe('mumbai');
        expect(me.body.data.area).toBe('Andheri');

        const userRow = await db.query('SELECT full_name FROM users WHERE id = $1', [org.user_id]);
        expect(userRow.rows[0].full_name).toBe('New Contact Person');
      });

    it('updates only the one field provided, leaving the rest untouched', async () => {
      const org = await registerOrganisation('0101');

      await request(app.getHttpServer())
        .patch('/v1/organisation/profile')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ area: 'Koramangala' })
        .expect(200);

      const me = await request(app.getHttpServer())
        .get('/v1/organisation/me')
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(me.body.data.area).toBe('Koramangala');
      expect(me.body.data.organisation_name).toBe('Enhancements Test Org');
      expect(me.body.data.contact_person_name).toBe('Test Contact');
    });

    it('rejects an unrecognized organisation_type (GEN_001)', async () => {
      const org = await registerOrganisation('0102');
      const res = await request(app.getHttpServer())
        .patch('/v1/organisation/profile')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ organisation_type: 'not-a-real-type' })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).patch('/v1/organisation/profile').send({ area: 'X' }).expect(401);
    });
  });
});
