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
 * Runs against the real Supabase Postgres instance. caregiver_messages is
 * a genuine multi-row table (not a singleton like duty_requirements/
 * scope_of_work), so isolation here is by a distinctive message-text
 * marker rather than a snapshot/restore dance — every row this suite
 * creates has its message text prefixed with TEST_MARKER, and cleanup
 * deletes exactly those rows, never touching the real seeded content.
 */
describe('Caregiver Messages (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let superAdminToken: string;

  const testPhone = (suffix: string) => `+91700011${suffix}`;
  const TEST_MARKER = 'E2E_TEST_MARKER_CAREGIVER_MESSAGES';

  async function cleanupMessages() {
    await db.query('DELETE FROM caregiver_messages WHERE message LIKE $1', [`${TEST_MARKER}%`]);
  }

  async function cleanupUsers() {
    await db.query(
      `DELETE FROM audit_logs WHERE user_id IN (SELECT id FROM users WHERE phone LIKE '+91700011%')
         OR target_user_id IN (SELECT id FROM users WHERE phone LIKE '+91700011%')`,
    );
    await db.query("DELETE FROM users WHERE phone LIKE '+91700011%'");
  }

  beforeAll(async () => {
    db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    await db.connect();
    await cleanupMessages();
    await cleanupUsers();

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
       VALUES ($1, $2, $3, 'Caregiver Messages E2E Super Admin', 'super_admin', true)`,
      ['caregiver-messages-super-admin-e2e@e2e-test.local', testPhone('0999'), passwordHash],
    );
    const login = await request(app.getHttpServer())
      .post('/v1/auth/login/email')
      .send({ email: 'caregiver-messages-super-admin-e2e@e2e-test.local', password: 'AdminPass123' })
      .expect(200);
    superAdminToken = login.body.data.access_token;
  });

  afterEach(async () => {
    await cleanupMessages();
  });

  afterAll(async () => {
    try {
      await cleanupMessages();
      await cleanupUsers();
    } finally {
      await db.end();
      await app.close();
    }
  });

  describe('GET /v1/caregiver-messages (public)', () => {
    it('requires no auth and only returns enabled rows', async () => {
      const created = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'job_applied',
          icon: 'person_add',
          message: `${TEST_MARKER} enabled message`,
          display_order: 9999,
          enabled: true,
        })
        .expect(201);
      const disabled = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'job_applied',
          icon: 'person_add',
          message: `${TEST_MARKER} disabled message`,
          display_order: 9999,
          enabled: false,
        })
        .expect(201);

      const res = await request(app.getHttpServer()).get('/v1/caregiver-messages').expect(200);
      const messages: string[] = res.body.data.map((m: { message: string }) => m.message);
      expect(messages).toContain(created.body.data.message);
      expect(messages).not.toContain(disabled.body.data.message);
    });
  });

  describe('GET /v1/admin/caregiver-messages', () => {
    it('returns every row including disabled ones, admin-only', async () => {
      await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'welcome',
          icon: 'waving_hand',
          message: `${TEST_MARKER} disabled admin-list message`,
          display_order: 9999,
          enabled: false,
        })
        .expect(201);

      const res = await request(app.getHttpServer())
        .get('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);
      const messages: string[] = res.body.data.map((m: { message: string }) => m.message);
      expect(messages).toContain(`${TEST_MARKER} disabled admin-list message`);
    });

    it('rejects an unauthenticated request', async () => {
      await request(app.getHttpServer()).get('/v1/admin/caregiver-messages').expect(401);
    });
  });

  describe('POST /v1/admin/caregiver-messages', () => {
    it('creates a message and audit-logs it', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'job_accepted',
          icon: 'check_circle',
          message: `${TEST_MARKER} accepted message {job_id}`,
          display_order: 20,
        })
        .expect(201);

      expect(res.body.data.event).toBe('job_accepted');
      expect(res.body.data.enabled).toBe(true);

      const audit = await db.query(
        "SELECT * FROM audit_logs WHERE action = 'caregiver_message_created' AND entity_id = $1",
        [res.body.data.id],
      );
      expect(audit.rows.length).toBe(1);
    });

    it('rejects an invalid event with GEN_001', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'not_a_real_event',
          icon: 'person_add',
          message: `${TEST_MARKER} bad event`,
          display_order: 10,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });

    it('rejects an invalid icon with GEN_001', async () => {
      const res = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'welcome',
          icon: 'not_a_real_icon',
          message: `${TEST_MARKER} bad icon`,
          display_order: 10,
        })
        .expect(400);
      expect(res.body.error.code).toBe('GEN_001');
    });
  });

  describe('PATCH /v1/admin/caregiver-messages/:id', () => {
    it('updates the message and audit-logs before/after', async () => {
      const created = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'job_rejected',
          icon: 'cancel',
          message: `${TEST_MARKER} to be edited`,
          display_order: 30,
        })
        .expect(201);

      const updated = await request(app.getHttpServer())
        .patch(`/v1/admin/caregiver-messages/${created.body.data.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ message: `${TEST_MARKER} edited text`, enabled: false })
        .expect(200);

      expect(updated.body.data.message).toBe(`${TEST_MARKER} edited text`);
      expect(updated.body.data.enabled).toBe(false);
      // Untouched fields survive the partial update.
      expect(updated.body.data.icon).toBe('cancel');

      const audit = await db.query(
        "SELECT * FROM audit_logs WHERE action = 'caregiver_message_updated' AND entity_id = $1",
        [created.body.data.id],
      );
      expect(audit.rows.length).toBe(1);
    });

    it('404s for a message id that does not exist', async () => {
      await request(app.getHttpServer())
        .patch('/v1/admin/caregiver-messages/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({ message: `${TEST_MARKER} nope` })
        .expect(404);
    });
  });

  describe('DELETE /v1/admin/caregiver-messages/:id', () => {
    it('deletes the message and audit-logs it', async () => {
      const created = await request(app.getHttpServer())
        .post('/v1/admin/caregiver-messages')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .send({
          event: 'job_closed',
          icon: 'task_alt',
          message: `${TEST_MARKER} to be deleted`,
          display_order: 40,
        })
        .expect(201);

      await request(app.getHttpServer())
        .delete(`/v1/admin/caregiver-messages/${created.body.data.id}`)
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(200);

      const remaining = await db.query('SELECT * FROM caregiver_messages WHERE id = $1', [
        created.body.data.id,
      ]);
      expect(remaining.rows.length).toBe(0);

      const audit = await db.query(
        "SELECT * FROM audit_logs WHERE action = 'caregiver_message_deleted' AND entity_id = $1",
        [created.body.data.id],
      );
      expect(audit.rows.length).toBe(1);
    });

    it('404s for a message id that does not exist', async () => {
      await request(app.getHttpServer())
        .delete('/v1/admin/caregiver-messages/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${superAdminToken}`)
        .expect(404);
    });
  });
});
