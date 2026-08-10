import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { AppException } from '../common/exceptions/app.exception';
import { UserRole, VerificationStatus } from '@vitacare/shared-constants';

describe('AuthService', () => {
  let service: AuthService;
  let db: any;
  let usersRepo: any;
  let caregiverProfilesRepo: any;
  let caregiverLanguagesRepo: any;
  let refreshTokensRepo: any;
  let tokenService: any;
  let emailService: any;
  let auditService: any;

  const baseUser = {
    id: 'user-1',
    email: null,
    phone: '+919876543210',
    password_hash: null,
    code_hash: null,
    full_name: 'Ramesh Kumar',
    role: UserRole.CAREGIVER,
    is_active: true,
  };

  beforeEach(() => {
    db = { withTransaction: jest.fn() };
    usersRepo = { findByPhone: jest.fn(), findByEmail: jest.fn(), findById: jest.fn() };
    caregiverProfilesRepo = { create: jest.fn(), findByUserId: jest.fn() };
    caregiverLanguagesRepo = { createMany: jest.fn() };
    refreshTokensRepo = {
      create: jest.fn(),
      findActiveById: jest.fn(),
      revoke: jest.fn(),
      revokeAllForUser: jest.fn(),
      pruneStaleForUser: jest.fn(),
    };
    tokenService = {
      signAccessToken: jest.fn().mockReturnValue('access-token'),
      signRefreshToken: jest
        .fn()
        .mockReturnValue({ token: 'refresh-token', expiresAt: new Date() }),
      verifyRefreshToken: jest.fn(),
    };

    refreshTokensRepo.create.mockResolvedValue({ id: 'rt-1' });
    emailService = { sendToAdmin: jest.fn(), send: jest.fn() };
    auditService = { log: jest.fn() };

    service = new AuthService(
      db,
      usersRepo,
      caregiverProfilesRepo,
      caregiverLanguagesRepo,
      refreshTokensRepo,
      tokenService,
      emailService,
      auditService,
    );
  });

  describe('register', () => {
    it('throws AUTH_001 when phone already registered', async () => {
      usersRepo.findByPhone.mockResolvedValue(baseUser);
      await expect(
        service.register({
          phone: baseUser.phone,
          full_name: 'X',
          gender: 'male' as any,
          age: 30,
          languages: ['hindi'] as any,
          code: '1234',
        }),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
    });

    it('creates user + profile + languages in a transaction and returns pending_call', async () => {
      usersRepo.findByPhone.mockResolvedValue(null);
      const client = { query: jest.fn().mockResolvedValue({ rows: [baseUser] }) };
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));
      caregiverProfilesRepo.create.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.PENDING_CALL,
      });

      const result = await service.register({
        phone: baseUser.phone,
        full_name: 'Ramesh Kumar',
        gender: 'male' as any,
        age: 30,
        languages: ['hindi', 'english'] as any,
        code: '1234',
      });

      expect(result.verification_status).toBe('pending_call');
      expect(result.user_id).toBe(baseUser.id);
      expect(result.profile_id).toBe('profile-1');
      expect(caregiverLanguagesRepo.createMany).toHaveBeenCalledWith(
        'profile-1',
        ['hindi', 'english'],
        client,
      );
      expect(emailService.sendToAdmin).toHaveBeenCalledWith(
        expect.stringContaining('registration'),
        expect.stringContaining('Ramesh Kumar'),
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: baseUser.id,
          action: 'registration',
          entityType: 'users',
          entityId: baseUser.id,
        }),
      );
    });

    it('hashes the code and stores it on the new user row (login code is set from registration onward)', async () => {
      usersRepo.findByPhone.mockResolvedValue(null);
      const client = { query: jest.fn().mockResolvedValue({ rows: [baseUser] }) };
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));
      caregiverProfilesRepo.create.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.PENDING_CALL,
      });

      await service.register({
        phone: baseUser.phone,
        full_name: 'Ramesh Kumar',
        gender: 'male' as any,
        age: 30,
        languages: ['hindi'] as any,
        code: '1234',
      });

      const [insertQuery, insertParams] = client.query.mock.calls[0];
      expect(insertQuery).toContain('code_hash');
      const storedHash = insertParams[3];
      expect(storedHash).not.toBe('1234');
      await expect(bcrypt.compare('1234', storedHash)).resolves.toBe(true);
    });
  });

  describe('loginCode', () => {
    it('throws AUTH_008 when code_hash is null', async () => {
      usersRepo.findByPhone.mockResolvedValue(baseUser);
      await expect(
        service.loginCode({ phone: baseUser.phone, code: '1234' }),
      ).rejects.toMatchObject({ code: 'AUTH_008' });
    });

    it('throws AUTH_008 when code does not match', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhone.mockResolvedValue({ ...baseUser, code_hash: codeHash });
      await expect(
        service.loginCode({ phone: baseUser.phone, code: '9999' }),
      ).rejects.toMatchObject({ code: 'AUTH_008' });
    });

    it('succeeds when code matches', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhone.mockResolvedValue({ ...baseUser, code_hash: codeHash });
      caregiverProfilesRepo.findByUserId.mockResolvedValue({
        verification_status: VerificationStatus.AVAILABLE,
        advanced_details_completed: true,
      });
      const result = await service.loginCode({ phone: baseUser.phone, code: '1234' });
      expect(result.verification_status).toBe('available');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: baseUser.id, action: 'login' }),
      );
    });
  });

  describe('loginEmail', () => {
    const adminUser = {
      ...baseUser,
      role: UserRole.ADMIN,
      email: 'admin@vitacasahealth.in',
      password_hash: '',
    };

    it('throws AUTH_003 when user not found', async () => {
      usersRepo.findByEmail.mockResolvedValue(null);
      await expect(
        service.loginEmail({ email: 'x@y.com', password: 'secret1' }),
      ).rejects.toMatchObject({ code: 'AUTH_003' });
    });

    it('throws AUTH_003 when user is a caregiver (not admin)', async () => {
      usersRepo.findByEmail.mockResolvedValue({ ...baseUser, email: 'c@y.com' });
      await expect(
        service.loginEmail({ email: 'c@y.com', password: 'secret1' }),
      ).rejects.toMatchObject({ code: 'AUTH_003' });
    });

    it('throws AUTH_003 on wrong password', async () => {
      const passwordHash = await bcrypt.hash('correct-pass', 4);
      usersRepo.findByEmail.mockResolvedValue({ ...adminUser, password_hash: passwordHash });
      await expect(
        service.loginEmail({ email: adminUser.email, password: 'wrong-pass' }),
      ).rejects.toMatchObject({ code: 'AUTH_003' });
    });

    it('returns null verification_status for admin on success', async () => {
      const passwordHash = await bcrypt.hash('correct-pass', 4);
      usersRepo.findByEmail.mockResolvedValue({ ...adminUser, password_hash: passwordHash });
      const result = await service.loginEmail({
        email: adminUser.email,
        password: 'correct-pass',
      });
      expect(result.verification_status).toBeNull();
      expect(result.access_token).toBe('access-token');
    });
  });

  describe('refresh', () => {
    it('throws AUTH_006 on invalid JWT', async () => {
      tokenService.verifyRefreshToken.mockImplementation(() => {
        throw new Error('bad token');
      });
      await expect(service.refresh('garbage')).rejects.toMatchObject({ code: 'AUTH_006' });
    });

    it('throws AUTH_006 when the DB row is missing/revoked', async () => {
      tokenService.verifyRefreshToken.mockReturnValue({
        sub: 'user-1',
        jti: 'rt-1',
        type: 'refresh',
      });
      refreshTokensRepo.findActiveById.mockResolvedValue(null);
      await expect(service.refresh('token')).rejects.toMatchObject({ code: 'AUTH_006' });
    });

    it('throws AUTH_006 when the stored hash does not match (rotated/stale token)', async () => {
      tokenService.verifyRefreshToken.mockReturnValue({
        sub: 'user-1',
        jti: 'rt-1',
        type: 'refresh',
      });
      const storedHash = await bcrypt.hash('a-different-token', 4);
      refreshTokensRepo.findActiveById.mockResolvedValue({
        id: 'rt-1',
        user_id: 'user-1',
        token_hash: storedHash,
      });
      await expect(service.refresh('token')).rejects.toMatchObject({ code: 'AUTH_006' });
    });

    it('rotates: revokes old row and issues new tokens on success', async () => {
      tokenService.verifyRefreshToken.mockReturnValue({
        sub: 'user-1',
        jti: 'rt-1',
        type: 'refresh',
      });
      const storedHash = await bcrypt.hash('the-token', 4);
      refreshTokensRepo.findActiveById.mockResolvedValue({
        id: 'rt-1',
        user_id: 'user-1',
        token_hash: storedHash,
      });
      usersRepo.findById.mockResolvedValue(baseUser);

      const result = await service.refresh('the-token');
      expect(refreshTokensRepo.revoke).toHaveBeenCalledWith('rt-1');
      expect(result.access_token).toBe('access-token');
    });
  });

  describe('logout', () => {
    it('revokes all refresh tokens for the user', async () => {
      await service.logout('user-1');
      expect(refreshTokensRepo.revokeAllForUser).toHaveBeenCalledWith('user-1');
    });
  });
});

describe('AppException', () => {
  it('resolves status and message from the shared error catalog', () => {
    const err = new AppException('AUTH_001');
    expect(err.getStatus()).toBe(409);
    expect(err.message).toBe('Phone number is already registered');
    expect(err.code).toBe('AUTH_001');
  });

  it('falls back to GEN_003 for an unknown code', () => {
    const err = new AppException('NOT_A_REAL_CODE');
    expect(err.getStatus()).toBe(500);
    expect(err.code).toBe('GEN_003');
  });
});
