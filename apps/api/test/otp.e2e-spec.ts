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
import { Msg91Service } from '../src/otp/msg91.service';

/**
 * Runs against the real Supabase Postgres instance. Uses the
 * +91700006xxxx test phone range (distinct from every other e2e suite —
 * see the convention note in auth.e2e-spec.ts).
 *
 * otp_auth_settings is a 2-row GLOBAL singleton (one per app), not scoped
 * by phone prefix like everything else here — same situation as
 * app_min_versions in app-config.e2e-spec.ts, so this suite follows that
 * exact precedent: snapshot the real rows in beforeAll, restore them
 * (including updated_by) in afterAll BEFORE deleting any test users.
 * Restoring updated_by specifically matters — the admin PATCH test below
 * sets it to this suite's own throwaway super_admin id, and deleting that
 * user while otp_auth_settings.updated_by still points at it violates the
 * users FK and (without care) can leave a dangling DB client that hangs
 * the whole Jest process on exit.
 */
describe('OTP Auth (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;
  let msg91Service: { sendOtp: jest.Mock };
  let originalOtpSettingsRows: Array<{
    app: string;
    enabled: boolean;
    updated_by: string | null;
    updated_at: Date;
  }>;

  const testPhone = (suffix: string) => `+91700006${suffix}`;

  const registerDtoBase = {
    full_name: 'Ramesh Kumar',
    gender: 'male',
    age: 30,
    languages: ['hindi'],
    religion: 'hindu',
    highest_qualification: 'rn_above_2_years',
    terms_accepted: true,
  };

  async function cleanupUsers() {
    await db.query("DELETE FROM otp_verifications WHERE phone LIKE '+91700006%'");
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700006%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700006%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700006%'");
  }

  async function restoreOriginalOtpSettings() {
    for (const row of originalOtpSettingsRows) {
      await db.query(
        `UPDATE otp_auth_settings SET enabled = $2, updated_by = $3, updated_at = $4 WHERE app = $1`,
        [row.app, row.enabled, row.updated_by, row.updated_at],
      );
    }
  }

  function lastSentOtp(): string {
    const calls = msg91Service.sendOtp.mock.calls;
    return calls[calls.length - 1][1];
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupUsers();

    const rows = await db.query('SELECT * FROM otp_auth_settings');
    originalOtpSettingsRows = rows.rows;
    // Every test in this file assumes both apps start OFF (the seeded
    // default) — restore-on-teardown preserves whatever was really there
    // before the suite ran, but the suite itself still needs a known
    // starting point to run against.
    await db.query('UPDATE otp_auth_settings SET enabled = false');

    msg91Service = { sendOtp: jest.fn().mockResolvedValue(undefined) };
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(EmailService)
      .useValue({ send: jest.fn(), sendToAdmin: jest.fn() })
      .overrideProvider(Msg91Service)
      .useValue(msg91Service)
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
       VALUES ($1, $2, $3, 'OTP E2E Super Admin', 'super_admin', true)`,
      ['otp-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'otp-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterEach(async () => {
    // Last-resort safety net in case a test's own try/finally reset didn't
    // run (e.g. an assertion threw before reaching it) — restores both
    // rows to the pre-suite snapshot, not just enabled=false, so
    // updated_by never lingers pointing at this suite's throwaway admin.
    await restoreOriginalOtpSettings();
  });

  afterAll(async () => {
    try {
      // Must run before cleanupUsers() — otp_auth_settings.updated_by can
      // reference this suite's throwaway admin, and deleting that user
      // while the FK still points at it throws (see file header comment).
      await restoreOriginalOtpSettings();
      await cleanupUsers();
    } finally {
      // Guaranteed even if the cleanup above throws — an unclosed db
      // client/app here is what turns a cleanup failure into a Jest
      // process that hangs indefinitely instead of just failing the test.
      await db.end();
      await app.close();
    }
  });

  describe('POST /v1/auth/otp/send + POST /v1/auth/otp/verify', () => {
    it('sends and verifies an OTP, returning a phone_verification_token', async () => {
      const phone = testPhone('0001');
      await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'register' })
        .expect(200);
      expect(msg91Service.sendOtp).toHaveBeenCalledWith(phone, expect.stringMatching(/^\d{6}$/));

      const verify = await request(app.getHttpServer())
        .post('/v1/auth/otp/verify')
        .send({ phone, app: 'nursejobs', purpose: 'register', otp: lastSentOtp() })
        .expect(200);
      expect(verify.body.data.phone_verification_token).toEqual(expect.any(String));
    });

    it('rejects a wrong OTP with AUTH_012', async () => {
      const phone = testPhone('0002');
      await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'register' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/auth/otp/verify')
        .send({ phone, app: 'nursejobs', purpose: 'register', otp: '000000' })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_012');
    });

    it('locks out with AUTH_013 after 5 wrong attempts', async () => {
      const phone = testPhone('0003');
      await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'register' })
        .expect(200);

      for (let i = 0; i < 4; i++) {
        const res = await request(app.getHttpServer())
          .post('/v1/auth/otp/verify')
          .send({ phone, app: 'nursejobs', purpose: 'register', otp: '000000' })
          .expect(401);
        expect(res.body.error.code).toBe('AUTH_012');
      }

      const locked = await request(app.getHttpServer())
        .post('/v1/auth/otp/verify')
        .send({ phone, app: 'nursejobs', purpose: 'register', otp: '000000' })
        .expect(429);
      expect(locked.body.error.code).toBe('AUTH_013');
    });

    it('rejects a resend inside the cooldown window with GEN_004', async () => {
      const phone = testPhone('0004');
      await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'register' })
        .expect(200);

      const res = await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'register' })
        .expect(429);
      expect(res.body.error.code).toBe('GEN_004');
    });

    it('scopes an OTP to its purpose — a register OTP cannot verify a login attempt', async () => {
      const phone = testPhone('0005');
      await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'register' })
        .expect(200);
      const otp = lastSentOtp();

      const res = await request(app.getHttpServer())
        .post('/v1/auth/otp/verify')
        .send({ phone, app: 'nursejobs', purpose: 'login', otp })
        .expect(401);
      expect(res.body.error.code).toBe('AUTH_012');
    });
  });

  describe('registration requires a verification token once OTP mode is enabled', () => {
    it('rejects a code-only body with AUTH_010 while nursejobs OTP mode is on', async () => {
      const phone = testPhone('0010');
      await db.query("UPDATE otp_auth_settings SET enabled = true WHERE app = 'nursejobs'");
      try {
        const res = await request(app.getHttpServer())
          .post('/v1/auth/register')
          .send({ ...registerDtoBase, phone, code: '1234' })
          .expect(400);
        expect(res.body.error.code).toBe('AUTH_010');
      } finally {
        await db.query("UPDATE otp_auth_settings SET enabled = false WHERE app = 'nursejobs'");
      }
    });
  });

  describe('full register -> login round trip via OTP, and the revert safety net', () => {
    it('registers with no PIN set, and /auth/login/otp still works after OTP mode is disabled again', async () => {
      const phone = testPhone('0011');
      let userId: string;

      await db.query("UPDATE otp_auth_settings SET enabled = true WHERE app = 'nursejobs'");
      try {
        await request(app.getHttpServer())
          .post('/v1/auth/otp/send')
          .send({ phone, app: 'nursejobs', purpose: 'register' })
          .expect(200);
        const registerToken = (
          await request(app.getHttpServer())
            .post('/v1/auth/otp/verify')
            .send({ phone, app: 'nursejobs', purpose: 'register', otp: lastSentOtp() })
            .expect(200)
        ).body.data.phone_verification_token;

        const register = await request(app.getHttpServer())
          .post('/v1/auth/register')
          .send({ ...registerDtoBase, phone, phone_verification_token: registerToken })
          .expect(201);
        userId = register.body.data.user_id;
        expect(register.body.data.access_token).toEqual(expect.any(String));
      } finally {
        await db.query("UPDATE otp_auth_settings SET enabled = false WHERE app = 'nursejobs'");
      }

      const row = await db.query('SELECT code_hash FROM users WHERE id = $1', [userId]);
      expect(row.rows[0].code_hash).toBeNull();

      // OTP mode is OFF again now — PIN login correctly rejects this
      // PIN-less account...
      await request(app.getHttpServer())
        .post('/v1/auth/login/code')
        .send({ phone, code: '0000', app: 'nursejobs' })
        .expect(401);

      // ...but /auth/login/otp is never flag-gated, so it still works.
      await request(app.getHttpServer())
        .post('/v1/auth/otp/send')
        .send({ phone, app: 'nursejobs', purpose: 'login' })
        .expect(200);
      const loginToken = (
        await request(app.getHttpServer())
          .post('/v1/auth/otp/verify')
          .send({ phone, app: 'nursejobs', purpose: 'login', otp: lastSentOtp() })
          .expect(200)
      ).body.data.phone_verification_token;

      const login = await request(app.getHttpServer())
        .post('/v1/auth/login/otp')
        .send({ phone, app: 'nursejobs', phone_verification_token: loginToken })
        .expect(200);
      expect(login.body.data.user_id).toBe(userId);
    });
  });

  describe('GET/PATCH /v1/admin/otp-settings', () => {
    it('rejects a non-admin caller with 403', async () => {
      const phone = testPhone('0020');
      const register = await request(app.getHttpServer())
        .post('/v1/auth/register')
        .send({ ...registerDtoBase, phone, code: '1234' })
        .expect(201);
      const caregiverToken = register.body.data.access_token;

      await request(app.getHttpServer())
        .get('/v1/admin/otp-settings')
        .set('Authorization', `Bearer ${caregiverToken}`)
        .expect(403);
    });

    it('lists both apps and lets a super_admin toggle one', async () => {
      const list = await request(app.getHttpServer())
        .get('/v1/admin/otp-settings')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      expect(list.body.data.map((r: { app: string }) => r.app).sort()).toEqual(['nursejobs', 'nursenow']);

      const patch = await request(app.getHttpServer())
        .patch('/v1/admin/otp-settings/nursejobs')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ enabled: true })
        .expect(200);
      expect(patch.body.data.enabled).toBe(true);
    });
  });

  describe('GET /v1/auth/otp-settings (public)', () => {
    it('returns the current enabled state, unauthenticated', async () => {
      const res = await request(app.getHttpServer()).get('/v1/auth/otp-settings?app=nursejobs').expect(200);
      expect(res.body.data).toEqual({ enabled: false });
    });

    it('rejects an unrecognized app value at the DTO layer', async () => {
      const res = await request(app.getHttpServer()).get('/v1/auth/otp-settings?app=not-a-real-app').expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });
  });
});
