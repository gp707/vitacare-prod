import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import * as bcrypt from 'bcrypt';
import { createClient } from '@supabase/supabase-js';
import { AppModule } from '../src/app.module';
import { GlobalExceptionFilter } from '../src/common/filters/global-exception.filter';
import { TransformInterceptor } from '../src/common/interceptors/transform.interceptor';
import { validationExceptionFactory } from '../src/common/pipes/validation-exception.factory';
import { EmailService } from '../src/email/email.service';
import { FcmService } from '../src/fcm/fcm.service';

/**
 * Runs against the real Supabase Postgres. Uses the +91700004xxxx test
 * phone range (distinct from every other e2e suite). Organisation accounts
 * and caregivers created by this suite are cleaned up by phone prefix;
 * organisation_requirements/applications are cleaned up by posted_by.
 */
describe('Organisation (NurseNow) (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let fcmService: { sendToUser: jest.Mock; sendToAllCaregivers: jest.Mock };
  const storage = createClient(
    process.env.SUPABASE_URL as string,
    process.env.SUPABASE_SERVICE_ROLE_KEY as string,
  );

  const testPhone = (suffix: string) => `+91700004${suffix}`;
  // Caregivers created by this suite share the same +91700004 prefix (so
  // one cleanup() covers everyone) but a disjoint suffix range (1xx) from
  // organisation accounts (0xx) to avoid phone collisions.
  const caregiverPhone = (suffix: string) => `+91700004${suffix}`;

  async function cleanup() {
    await db.query(
      `DELETE FROM organisation_requirement_applications WHERE requirement_id IN (
         SELECT id FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700004%')
       )`,
    );
    await db.query(
      `DELETE FROM organisation_requirements WHERE posted_by IN (SELECT id FROM users WHERE phone LIKE '+91700004%')`,
    );
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700004%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700004%')`,
    );
    await db.query("DELETE FROM organisation_profiles WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700004%')");
    await db.query("DELETE FROM users WHERE phone LIKE '+91700004%'");
  }

  async function registerOrganisation(phoneSuffix: string, organisationName = 'Test Hospital') {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register/organisation')
      .send({
        phone: testPhone(phoneSuffix),
        code: '1234',
        organisation_name: organisationName,
        contact_person_name: 'Test Contact',
        organisation_type: 'hospital',
        city: 'bangalore',
        area: 'Indiranagar',
      })
      .expect(201);
    return res.body.data as { user_id: string; access_token: string };
  }

  async function registerCaregiver(phoneSuffix: string) {
    const res = await request(app.getHttpServer())
      .post('/v1/auth/register')
      .send({
        phone: caregiverPhone(phoneSuffix),
        full_name: 'Organisation Test Caregiver',
        gender: 'female',
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
    ...overrides,
  });

  const approvalPayload = (overrides: Record<string, unknown> = {}) => ({
    type_of_nurse: 'registered_nurse',
    frequency_of_care: 'monthly',
    salary_amount: 40000,
    schedule_type: 'specific_days',
    schedule_repeat: 'monthly',
    specific_days: [3, 12, 20],
    accommodation_provided: true,
    food_provided: false,
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

    const passwordHash = await bcrypt.hash('AdminPass123', 4);
    await db.query(
      `INSERT INTO users (email, phone, password_hash, full_name, role, is_active)
       VALUES ($1, $2, $3, 'Organisation E2E Super Admin', 'super_admin', true)`,
      ['organisation-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'organisation-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterAll(async () => {
    await cleanup();
    await db.end();
    await app.close();
  });

  describe('POST /v1/auth/register/organisation + login', () => {
    it('registers, returns a token, and no verification_status', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register/organisation')
        .send({
          phone: testPhone('0001'),
          code: '1234',
          organisation_name: 'City Hospital',
          contact_person_name: 'Ravi Sharma',
          organisation_type: 'hospital',
          city: 'bangalore',
          area: 'Indiranagar',
        })
        .expect(201);
      expect(res.body.data.access_token).toBeDefined();
      expect(res.body.data.verification_status).toBeUndefined();
    });

    it('rejects a duplicate phone (AUTH_001)', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/register/organisation')
        .send({
          phone: testPhone('0001'),
          code: '5678',
          organisation_name: 'Another Hospital',
          contact_person_name: 'Someone Else',
          organisation_type: 'clinic',
          city: 'mumbai',
          area: 'Bandra',
        })
        .expect(409);
      expect(res.body.error.code).toBe('AUTH_001');
    });

    it('logs back in with phone + code', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0001'), code: '1234', app: 'nursenow' })
        .expect(200);
      expect(res.body.data.access_token).toBeDefined();
    });
  });

  describe('GET /v1/organisation/me', () => {
    it("returns the caller's own identity + location, not a caregiver-style verification_status", async () => {
      const org = await registerOrganisation('0002', 'Sunrise Rehab');
      const res = await request(app.getHttpServer())
        .get('/v1/organisation/me')
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(res.body.data.organisation_name).toBe('Sunrise Rehab');
      expect(res.body.data.city).toBe('bangalore');
      expect(res.body.data.is_job_posting_blocked).toBe(false);
      expect(res.body.data.verification_status).toBeUndefined();
      // Human-friendly sequential id (migration 046), starts at 500 —
      // displayed client-side as "ORG-<n>".
      expect(res.body.data.org_number).toBeGreaterThanOrEqual(500);
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0120');
      await request(app.getHttpServer())
        .get('/v1/organisation/me')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(403);
    });
  });

  describe('POST /v1/organisation/requirements', () => {
    it('creates a pending_review requirement with no frequency_of_care/salary_amount visible yet', async () => {
      const org = await registerOrganisation('0003');
      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      expect(res.body.data.status).toBe('pending_review');
      expect(res.body.data.frequency_of_care).toBeNull();
      expect(res.body.data.salary_amount).toBeNull();
    });

    it('allows posting a second (and third) simultaneous requirement — no one-live limit like Individual', async () => {
      const org = await registerOrganisation('0004');
      await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload({ type_of_nurse: 'auxiliary_nurse' }))
        .expect(201);

      const mine = await request(app.getHttpServer())
        .get('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(mine.body.data).toHaveLength(2);
    });

    it('rejects a caregiver token (AUTH_007)', async () => {
      const caregiver = await registerCaregiver('0104');
      await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send(requirementPayload())
        .expect(403);
    });
  });

  describe('Admin approval / rejection of a pending_review requirement', () => {
    it('approving via PATCH /v1/admin/organisation-requirements/:id sets frequency_of_care/salary_amount and activates it', async () => {
      const org = await registerOrganisation('0005');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;

      const approved = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload())
        .expect(200);
      expect(approved.body.data.status).toBe('active');
      expect(approved.body.data.salary_amount).toBe(40000);
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalled();
    });

    it('GET /v1/admin/organisation-requirements filters by search (org name/ORG-JOB-<n> id), status, organisation_type, and city',
      async () => {
        const org = await registerOrganisation('0031', 'Filterable Org For Requirements');
        const created = await request(app.getHttpServer())
          .post('/v1/organisation/requirements')
          .set('Authorization', `Bearer ${org.access_token}`)
          .send(requirementPayload())
          .expect(201);
        const requirementId = created.body.data.id;

        const list = await request(app.getHttpServer())
          .get('/v1/admin/organisation-requirements?limit=100&search=Filterable Org For Requirements')
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(list.body.data).toHaveLength(1);
        const requirementNumber = list.body.data[0].requirement_number as number;

        const byDisplayId = await request(app.getHttpServer())
          .get(`/v1/admin/organisation-requirements?limit=100&search=ORG-JOB-${requirementNumber}`)
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(byDisplayId.body.data.map((r: { id: string }) => r.id)).toContain(requirementId);

        const byStatus = await request(app.getHttpServer())
          .get(
            '/v1/admin/organisation-requirements?limit=100&search=Filterable Org For Requirements&status=pending_review',
          )
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(byStatus.body.data).toHaveLength(1);

        const byWrongStatus = await request(app.getHttpServer())
          .get('/v1/admin/organisation-requirements?limit=100&search=Filterable Org For Requirements&status=active')
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(byWrongStatus.body.data).toHaveLength(0);

        const byType = await request(app.getHttpServer())
          .get(
            '/v1/admin/organisation-requirements?limit=100&search=Filterable Org For Requirements&organisation_type=hospital',
          )
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(byType.body.data).toHaveLength(1);

        const byCity = await request(app.getHttpServer())
          .get('/v1/admin/organisation-requirements?limit=100&search=Filterable Org For Requirements&city=bangalore')
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(byCity.body.data).toHaveLength(1);
      });

    it('GET /v1/admin/audit-logs resolves requirement_number/requirement_id for organisation_requirements entries, and target org_number when the org applicant is decided',
      async () => {
        const org = await registerOrganisation('0032', 'Audit Org Subject');
        const created = await request(app.getHttpServer())
          .post('/v1/organisation/requirements')
          .set('Authorization', `Bearer ${org.access_token}`)
          .send(requirementPayload())
          .expect(201);
        const requirementId = created.body.data.id;

        const auditList = await request(app.getHttpServer())
          .get('/v1/admin/audit-logs')
          .query({ action: 'org_requirement_posted', limit: 50 })
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        const auditEntry = auditList.body.data.find((e: { entity_id: string }) => e.entity_id === requirementId);
        expect(auditEntry).toBeDefined();
        expect(auditEntry.requirement_number).toEqual(expect.any(Number));
        expect(auditEntry.requirement_id).toBe(requirementId);

        await request(app.getHttpServer())
          .patch(`/v1/admin/organisations/${org.user_id}/block`)
          .set('Authorization', `Bearer ${superAdminToken}`)
          .send({ level: 'job_posting', reason: 'Audit target resolution test' })
          .expect(200);

        const blockAudit = await request(app.getHttpServer())
          .get('/v1/admin/audit-logs')
          .query({ target_user_id: org.user_id })
          .set('Authorization', `Bearer ${superAdminToken}`)
          .expect(200);
        expect(blockAudit.body.data).toHaveLength(1);
        expect(blockAudit.body.data[0].target_user_role).toBe('organisation');
        expect(blockAudit.body.data[0].target_org_number).toEqual(expect.any(Number));
        expect(blockAudit.body.data[0].target_caregiver_number).toBeNull();
      });

    it('date_range schedule requires start_date/end_date (ORG_001 otherwise) and end_date must not precede start_date', async () => {
      const org = await registerOrganisation('0006');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;

      const missingDates = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload({ schedule_type: 'date_range', specific_days: undefined }))
        .expect(400);
      expect(missingDates.body.error.code).toBe('ORG_001');

      const endBeforeStart = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(
          approvalPayload({
            schedule_type: 'date_range',
            specific_days: undefined,
            start_date: '2026-09-10',
            end_date: '2026-09-01',
          }),
        )
        .expect(400);
      expect(endBeforeStart.body.error.code).toBe('ORG_001');

      const approved = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(
          approvalPayload({
            schedule_type: 'date_range',
            specific_days: undefined,
            start_date: '2026-09-01',
            end_date: '2026-09-10',
          }),
        )
        .expect(200);
      expect(approved.body.data.schedule_type).toBe('date_range');
      expect(approved.body.data.start_date).toBe('2026-09-01');
      expect(approved.body.data.end_date).toBe('2026-09-10');
      expect(approved.body.data.specific_days).toBeNull();
    });

    it('specific_days schedule requires a non-empty day list (ORG_001 otherwise) and persists it', async () => {
      const org = await registerOrganisation('0028');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;

      const missingDays = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload({ schedule_type: 'specific_days', specific_days: undefined }))
        .expect(400);
      expect(missingDays.body.error.code).toBe('ORG_001');

      const approved = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload({ schedule_type: 'specific_days', schedule_repeat: 'monthly', specific_days: [5, 15, 25] }))
        .expect(200);
      expect(approved.body.data.schedule_type).toBe('specific_days');
      expect(approved.body.data.schedule_repeat).toBe('monthly');
      expect(approved.body.data.specific_days).toEqual([5, 15, 25]);
      expect(approved.body.data.start_date).toBeNull();
      expect(approved.body.data.end_date).toBeNull();
    });

    it('specific_days/weekly schedule stores ISO weekday numbers and rejects a value outside 1-7 (ORG_002)', async () => {
      const org = await registerOrganisation('0029');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;

      const invalidWeekday = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload({ schedule_type: 'specific_days', schedule_repeat: 'weekly', specific_days: [1, 12] }))
        .expect(400);
      expect(invalidWeekday.body.error.code).toBe('ORG_002');

      const approved = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload({ schedule_type: 'specific_days', schedule_repeat: 'weekly', specific_days: [1, 3, 5] }))
        .expect(200);
      expect(approved.body.data.schedule_type).toBe('specific_days');
      expect(approved.body.data.schedule_repeat).toBe('weekly');
      expect(approved.body.data.specific_days).toEqual([1, 3, 5]);
    });

    it('an approved (active) requirement shows up on GET /v1/caregiver/organisation-requirements, and a caregiver can apply', async () => {
      const org = await registerOrganisation('0007', 'Green Valley Clinic');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload())
        .expect(200);

      const caregiver = await registerCaregiver('0107');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);

      const list = await request(app.getHttpServer())
        .get('/v1/caregiver/organisation-requirements')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      const found = list.body.data.find((r: { id: string }) => r.id === requirementId);
      expect(found).toBeDefined();
      expect(found.organisation_name).toBe('Green Valley Clinic');

      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
    });

    it('the organisation can accept an applicant themselves, closing the requirement and assigning the caregiver', async () => {
      const org = await registerOrganisation('0008');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload())
        .expect(200);

      const caregiver = await registerCaregiver('0109');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const applicants = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${requirementId}/applications`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      const applicationId = applicants.body.data[0].id;

      await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${requirementId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ status: 'accepted' })
        .expect(200);

      const caregiverProfile = await db.query(
        'SELECT verification_status FROM caregiver_profiles WHERE user_id = $1',
        [caregiver.user_id],
      );
      expect(caregiverProfile.rows[0].verification_status).toBe('assigned');

      const requirementRow = await db.query('SELECT status FROM organisation_requirements WHERE id = $1', [
        requirementId,
      ]);
      expect(requirementRow.rows[0].status).toBe('closed');

      // Caregiver can now mark it complete, dropping back to available.
      const completion = await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/complete`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      expect(completion.body.data.verification_status).toBe('available');

      const assigned = await request(app.getHttpServer())
        .get('/v1/caregiver/organisation-requirements/assigned')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(200);
      expect(assigned.body.data).toHaveLength(1);
      expect(assigned.body.data[0].id).toBe(requirementId);
      expect(assigned.body.data[0].my_application.status).toBe('completed');
    });

    it("lets the organisation view an applicant's full profile, ownership-checked, including Aadhaar/qualification-document URLs", async () => {
      const org = await registerOrganisation('0026');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload())
        .expect(200);

      const caregiver = await registerCaregiver('0130');
      await request(app.getHttpServer())
        .post('/v1/caregiver/profile/documents')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .field('document_type', 'aadhaar')
        .attach('file', Buffer.from('fake aadhaar'), 'aadhaar.pdf')
        .expect(200);
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);
      const applicants = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${requirementId}/applications`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      const applicationId = applicants.body.data[0].id;

      const profile = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${requirementId}/applications/${applicationId}/profile`)
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(profile.body.data.profile_id).toBe(caregiver.profile_id);
      expect(profile.body.data.full_name).toBeDefined();
      expect(profile.body.data.aadhaar_document_url).toContain('aadhaar');
      const aadhaarContent = await fetch(profile.body.data.aadhaar_document_url).then((r) => r.text());
      expect(aadhaarContent).toBe('fake aadhaar');
      await storage.storage.from('caregiver-documents').remove([`${caregiver.profile_id}/aadhaar.pdf`]);

      // Ownership check: another organisation can't view this applicant.
      const outsider = await registerOrganisation('0027');
      const outsiderReq = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${outsider.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const forbidden = await request(app.getHttpServer())
        .get(`/v1/organisation/requirements/${outsiderReq.body.data.id}/applications/${applicationId}/profile`)
        .set('Authorization', `Bearer ${outsider.access_token}`)
        .expect(404);
      expect(forbidden.body.error.code).toBe('GEN_002');
    }, 30000);

    it("rejects deciding on another organisation's requirement (ownership check, GEN_002)", async () => {
      const owner = await registerOrganisation('0010');
      const outsider = await registerOrganisation('0011');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${owner.access_token}`)
        .send(requirementPayload())
        .expect(201);

      const res = await request(app.getHttpServer())
        .patch(`/v1/organisation/requirements/${created.body.data.id}/applications/nonexistent-app-id`)
        .set('Authorization', `Bearer ${outsider.access_token}`)
        .send({ status: 'accepted' })
        .expect(404);
      expect(res.body.error.code).toBe('GEN_002');
    });

    it('admin retains full parity — can decide an application on an organisation-posted requirement too', async () => {
      const org = await registerOrganisation('0012');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      const requirementId = created.body.data.id;
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload())
        .expect(200);

      const caregiver = await registerCaregiver('0113');
      await db.query("UPDATE caregiver_profiles SET verification_status = 'available' WHERE user_id = $1", [
        caregiver.user_id,
      ]);
      await request(app.getHttpServer())
        .post(`/v1/caregiver/organisation-requirements/${requirementId}/apply`)
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .send({ status: 'applied' })
        .expect(200);

      const adminDetail = await request(app.getHttpServer())
        .get(`/v1/admin/organisation-requirements/${requirementId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(adminDetail.body.data.organisation_name).toBe('Test Hospital');
      const applicationId = adminDetail.body.data.applications[0].id;

      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${requirementId}/applications/${applicationId}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ status: 'accepted' })
        .expect(200);
    });

    it('admin can reject a pending_review requirement with a reason, and it never goes live', async () => {
      const org = await registerOrganisation('0014');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);

      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${created.body.data.id}/reject`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ reason: 'Duplicate posting' })
        .expect(200);

      const mine = await request(app.getHttpServer())
        .get('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);
      expect(mine.body.data[0].status).toBe('closed');
      expect(mine.body.data[0].rejection_reason).toBe('Duplicate posting');
    });

    it('rejects rejecting a requirement that is not pending_review (JOB_011)', async () => {
      const org = await registerOrganisation('0015');
      const created = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${created.body.data.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send(approvalPayload())
        .expect(200);

      const res = await request(app.getHttpServer())
        .patch(`/v1/admin/organisation-requirements/${created.body.data.id}/reject`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ reason: 'Too late' })
        .expect(400);
      expect(res.body.error.code).toBe('JOB_011');
    });
  });

  describe('Admin blocking (GET/PATCH /v1/admin/organisations)', () => {
    it('lists organisations created by this suite', async () => {
      await registerOrganisation('0016');
      const res = await request(app.getHttpServer())
        .get('/v1/admin/organisations')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(res.body.data.length).toBeGreaterThan(0);
    });

    it('filters by search (org name/ORG-<n> id), organisation_type, city, and block_status', async () => {
      const org = await registerOrganisation('0030', 'Filterable Rehab Center');
      const list = await request(app.getHttpServer())
        .get('/v1/admin/organisations?limit=100&search=Filterable Rehab Center')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(list.body.data).toHaveLength(1);
      const orgNumber = list.body.data[0].org_number as number;

      const byDisplayId = await request(app.getHttpServer())
        .get(`/v1/admin/organisations?limit=100&search=ORG-${orgNumber}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(byDisplayId.body.data.map((o: { user_id: string }) => o.user_id)).toContain(org.user_id);

      const byType = await request(app.getHttpServer())
        .get('/v1/admin/organisations?limit=100&search=Filterable Rehab Center&organisation_type=hospital')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(byType.body.data).toHaveLength(1);

      const byWrongType = await request(app.getHttpServer())
        .get('/v1/admin/organisations?limit=100&search=Filterable Rehab Center&organisation_type=clinic')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(byWrongType.body.data).toHaveLength(0);

      const byCity = await request(app.getHttpServer())
        .get('/v1/admin/organisations?limit=100&search=Filterable Rehab Center&city=bangalore')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(byCity.body.data).toHaveLength(1);

      await request(app.getHttpServer())
        .patch(`/v1/admin/organisations/${org.user_id}/block`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'job_posting', reason: 'Filter test block' })
        .expect(200);

      const jobPostingBlocked = await request(app.getHttpServer())
        .get('/v1/admin/organisations?limit=100&search=Filterable Rehab Center&block_status=job_posting_blocked')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(jobPostingBlocked.body.data).toHaveLength(1);

      const activeOnly = await request(app.getHttpServer())
        .get('/v1/admin/organisations?limit=100&search=Filterable Rehab Center&block_status=active')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(activeOnly.body.data).toHaveLength(0);
    });

    it('job_posting_blocked rejects a new posting (JOB_010) but does not log the organisation out', async () => {
      const org = await registerOrganisation('0017');
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisations/${org.user_id}/block`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'job_posting', reason: 'Suspicious activity' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(403);
      expect(res.body.error.code).toBe('JOB_010');

      await request(app.getHttpServer())
        .get('/v1/organisation/me')
        .set('Authorization', `Bearer ${org.access_token}`)
        .expect(200);

      await request(app.getHttpServer())
        .patch(`/v1/admin/organisations/${org.user_id}/unblock`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'job_posting' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/v1/organisation/requirements')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send(requirementPayload())
        .expect(201);
    });

    it('a full block (level=full) rejects login entirely (AUTH_004), with the reason visible via admin detail', async () => {
      const org = await registerOrganisation('0018');
      await request(app.getHttpServer())
        .patch(`/v1/admin/organisations/${org.user_id}/block`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ level: 'full', reason: 'Fraudulent postings' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0018'), code: '1234', app: 'nursenow' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_004');

      const detail = await request(app.getHttpServer())
        .get(`/v1/admin/organisations/${org.user_id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(detail.body.data.is_active).toBe(false);
      expect(detail.body.data.block_reason).toBe('Fraudulent postings');
    });

    it('rejects a caregiver token (AUTH_007) — admin/organisations routes are admin-only', async () => {
      const caregiver = await registerCaregiver('0119');
      await request(app.getHttpServer())
        .get('/v1/admin/organisations')
        .set('Authorization', `Bearer ${caregiver.access_token}`)
        .expect(403);
    });
  });

  describe('PATCH /v1/organisation/profile/phone + /profile/code', () => {
    it('changes the phone number and the organisation can log in with it', async () => {
      const org = await registerOrganisation('0021');
      await request(app.getHttpServer())
        .patch('/v1/organisation/profile/phone')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ phone: testPhone('0022') })
        .expect(200);

      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0022'), code: '1234', app: 'nursenow' })
        .expect(200);
    });

    it('changes the login code and the organisation can log in with the new one only', async () => {
      const org = await registerOrganisation('0025');
      await request(app.getHttpServer())
        .patch('/v1/organisation/profile/code')
        .set('Authorization', `Bearer ${org.access_token}`)
        .send({ code: '4321' })
        .expect(200);

      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0025'), code: '4321', app: 'nursenow' })
        .expect(200);
      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone: testPhone('0025'), code: '1234', app: 'nursenow' })
        .expect(401);
    });
  });
});
