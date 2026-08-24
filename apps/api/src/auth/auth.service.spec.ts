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
  let caregiverPreferredCitiesRepo: any;
  let individualProfilesRepo: any;
  let organisationProfilesRepo: any;
  let refreshTokensRepo: any;
  let otpAuthSettingsRepo: any;
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
    usersRepo = { findByPhoneAndRoles: jest.fn(), findByEmail: jest.fn(), findById: jest.fn() };
    caregiverProfilesRepo = { create: jest.fn(), findByUserId: jest.fn() };
    caregiverLanguagesRepo = { createMany: jest.fn() };
    caregiverPreferredCitiesRepo = { createMany: jest.fn() };
    individualProfilesRepo = { create: jest.fn(), findByUserId: jest.fn() };
    organisationProfilesRepo = { create: jest.fn(), findByUserId: jest.fn() };
    refreshTokensRepo = {
      create: jest.fn(),
      findActiveById: jest.fn(),
      revoke: jest.fn(),
      revokeAllForUser: jest.fn(),
      pruneStaleForUser: jest.fn(),
    };
    // Default OFF for every existing test — OTP mode is opt-in per app, and
    // this keeps every pre-existing PIN-based test unaffected (regression
    // safety). Tests that specifically exercise OTP mode override this.
    otpAuthSettingsRepo = { findByApp: jest.fn().mockResolvedValue({ enabled: false }) };
    tokenService = {
      signAccessToken: jest.fn().mockReturnValue('access-token'),
      signRefreshToken: jest
        .fn()
        .mockReturnValue({ token: 'refresh-token', expiresAt: new Date() }),
      verifyRefreshToken: jest.fn(),
      verifyPhoneVerificationToken: jest.fn(),
    };

    refreshTokensRepo.create.mockResolvedValue({ id: 'rt-1' });
    emailService = { sendToAdmin: jest.fn(), send: jest.fn() };
    auditService = { log: jest.fn() };

    service = new AuthService(
      db,
      usersRepo,
      caregiverProfilesRepo,
      caregiverLanguagesRepo,
      caregiverPreferredCitiesRepo,
      individualProfilesRepo,
      organisationProfilesRepo,
      refreshTokensRepo,
      otpAuthSettingsRepo,
      tokenService,
      emailService,
      auditService,
    );
  });

  describe('register', () => {
    it('throws AUTH_001 when phone already registered', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(baseUser);
      await expect(
        service.register({
          phone: baseUser.phone,
          full_name: 'X',
          gender: 'male' as any,
          age: 30,
          languages: ['hindi'] as any,
          religion: 'hindu' as any,
          highest_qualification: 'rn_above_2_years' as any,
          terms_accepted: true,
          code: '1234',
        }),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
    });

    it('creates user + profile + languages in a transaction and returns pending_call', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
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
        religion: 'hindu' as any,
        highest_qualification: 'rn_above_2_years' as any,
        terms_accepted: true,
        code: '1234',
      });

      expect(result.verification_status).toBe('pending_call');
      expect(result.user_id).toBe(baseUser.id);
      expect(result.profile_id).toBe('profile-1');
      expect(caregiverProfilesRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ religion: 'hindu' }),
        client,
      );
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
          afterValue: expect.objectContaining({ religion: 'hindu' }),
        }),
      );
    });

    it('creates preferred cities when provided, skips when omitted', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
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
        religion: 'hindu' as any,
        highest_qualification: 'rn_above_2_years' as any,
        terms_accepted: true,
        preferred_cities: ['bangalore', 'mumbai'] as any,
        code: '1234',
      });
      expect(caregiverPreferredCitiesRepo.createMany).toHaveBeenCalledWith(
        'profile-1',
        ['bangalore', 'mumbai'],
        client,
      );

      caregiverPreferredCitiesRepo.createMany.mockClear();
      await service.register({
        phone: baseUser.phone,
        full_name: 'Ramesh Kumar',
        gender: 'male' as any,
        age: 30,
        languages: ['hindi'] as any,
        religion: 'hindu' as any,
        highest_qualification: 'rn_above_2_years' as any,
        terms_accepted: true,
        code: '1234',
      });
      expect(caregiverPreferredCitiesRepo.createMany).not.toHaveBeenCalled();
    });

    it('hashes the code and stores it on the new user row (login code is set from registration onward)', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
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
        religion: 'hindu' as any,
        highest_qualification: 'rn_above_2_years' as any,
        terms_accepted: true,
        code: '1234',
      });

      const [insertQuery, insertParams] = client.query.mock.calls[0];
      expect(insertQuery).toContain('code_hash');
      const storedHash = insertParams[3];
      expect(storedHash).not.toBe('1234');
      await expect(bcrypt.compare('1234', storedHash)).resolves.toBe(true);
    });

    it('when OTP mode is enabled for nursejobs, throws AUTH_010 if no phone_verification_token is given (code is ignored)', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      otpAuthSettingsRepo.findByApp.mockResolvedValue({ enabled: true });

      await expect(
        service.register({
          phone: baseUser.phone,
          full_name: 'Ramesh Kumar',
          gender: 'male' as any,
          age: 30,
          languages: ['hindi'] as any,
          religion: 'hindu' as any,
          highest_qualification: 'rn_above_2_years' as any,
          terms_accepted: true,
          code: '1234',
        }),
      ).rejects.toMatchObject({ code: 'AUTH_010' });
    });

    it('when OTP mode is enabled and code is omitted (PIN mode), throws AUTH_009', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      otpAuthSettingsRepo.findByApp.mockResolvedValue({ enabled: false });

      await expect(
        service.register({
          phone: baseUser.phone,
          full_name: 'Ramesh Kumar',
          gender: 'male' as any,
          age: 30,
          languages: ['hindi'] as any,
          religion: 'hindu' as any,
          highest_qualification: 'rn_above_2_years' as any,
          terms_accepted: true,
        } as any),
      ).rejects.toMatchObject({ code: 'AUTH_009' });
    });

    it('when OTP mode is enabled with a valid phone_verification_token, stores a null code_hash', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      otpAuthSettingsRepo.findByApp.mockResolvedValue({ enabled: true });
      tokenService.verifyPhoneVerificationToken.mockReturnValue({
        phone: baseUser.phone,
        app: 'nursejobs',
        purpose: 'register',
        type: 'phone_verification',
      });
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
        religion: 'hindu' as any,
        highest_qualification: 'rn_above_2_years' as any,
        terms_accepted: true,
        phone_verification_token: 'verified-token',
      } as any);

      const [, insertParams] = client.query.mock.calls[0];
      expect(insertParams[3]).toBeNull();
    });

    it('when OTP mode is enabled, a token issued for a different phone is rejected with AUTH_011', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      otpAuthSettingsRepo.findByApp.mockResolvedValue({ enabled: true });
      tokenService.verifyPhoneVerificationToken.mockReturnValue({
        phone: '+919999999999',
        app: 'nursejobs',
        purpose: 'register',
        type: 'phone_verification',
      });

      await expect(
        service.register({
          phone: baseUser.phone,
          full_name: 'Ramesh Kumar',
          gender: 'male' as any,
          age: 30,
          languages: ['hindi'] as any,
          religion: 'hindu' as any,
          highest_qualification: 'rn_above_2_years' as any,
          terms_accepted: true,
          phone_verification_token: 'verified-token',
        } as any),
      ).rejects.toMatchObject({ code: 'AUTH_011' });
    });
  });

  describe('registerIndividual', () => {
    const individualUser = { ...baseUser, role: UserRole.INDIVIDUAL };

    it('throws AUTH_001 when phone already registered', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(individualUser);
      await expect(
        service.registerIndividual({
          phone: individualUser.phone,
          full_name: 'Asha Patel',
          terms_accepted: true,
          code: '1234',
        }),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
    });

    it('creates user + individual_profiles in a transaction and returns no verification_status', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      const client = { query: jest.fn().mockResolvedValue({ rows: [individualUser] }) };
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));

      const result = await service.registerIndividual({
        phone: individualUser.phone,
        full_name: 'Asha Patel',
        terms_accepted: true,
        code: '1234',
      });

      expect(result.user_id).toBe(individualUser.id);
      expect(result).not.toHaveProperty('verification_status');
      expect(individualProfilesRepo.create).toHaveBeenCalledWith(individualUser.id, true, client);
      const [insertQuery, insertParams] = client.query.mock.calls[0];
      expect(insertQuery).toContain('code_hash');
      expect(insertParams).toEqual([individualUser.phone, 'Asha Patel', UserRole.INDIVIDUAL, expect.any(String)]);
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: individualUser.id, action: 'registration' }),
      );
    });
  });

  describe('registerOrganisation', () => {
    const orgUser = { ...baseUser, role: UserRole.ORGANISATION, full_name: 'Ravi Sharma' };
    const orgDto = {
      phone: orgUser.phone,
      code: '1234',
      organisation_name: 'City Hospital',
      contact_person_name: 'Ravi Sharma',
      organisation_type: 'hospital',
      city: 'bangalore',
      area: 'Indiranagar',
      terms_accepted: true,
    };

    it('throws AUTH_001 when phone already registered', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(orgUser);
      await expect(service.registerOrganisation(orgDto)).rejects.toMatchObject({ code: 'AUTH_001' });
    });

    it('creates user (full_name = contact_person_name) + organisation_profiles, returns no verification_status', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      const client = { query: jest.fn().mockResolvedValue({ rows: [orgUser] }) };
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));

      const result = await service.registerOrganisation(orgDto);

      expect(result.user_id).toBe(orgUser.id);
      expect(result).not.toHaveProperty('verification_status');
      expect(organisationProfilesRepo.create).toHaveBeenCalledWith(
        orgUser.id,
        {
          organisation_name: 'City Hospital',
          contact_person_name: 'Ravi Sharma',
          organisation_type: 'hospital',
          city: 'bangalore',
          area: 'Indiranagar',
          terms_accepted: true,
        },
        client,
      );
      const [insertQuery, insertParams] = client.query.mock.calls[0];
      expect(insertQuery).toContain('code_hash');
      expect(insertParams).toEqual([orgUser.phone, 'Ravi Sharma', UserRole.ORGANISATION, expect.any(String)]);
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: orgUser.id, action: 'registration' }),
      );
    });
  });

  describe('loginCode', () => {
    it('throws AUTH_008 when code_hash is null', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(baseUser);
      await expect(
        service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursejobs' }),
      ).rejects.toMatchObject({ code: 'AUTH_008' });
    });

    it('throws AUTH_008 when code does not match', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ ...baseUser, code_hash: codeHash });
      await expect(
        service.loginCode({ phone: baseUser.phone, code: '9999', app: 'nursejobs' }),
      ).rejects.toMatchObject({ code: 'AUTH_008' });
    });

    it('succeeds when code matches', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ ...baseUser, code_hash: codeHash });
      caregiverProfilesRepo.findByUserId.mockResolvedValue({
        verification_status: VerificationStatus.AVAILABLE,
      });
      const result = await service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursejobs' });
      expect((result as { verification_status: string }).verification_status).toBe('available');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: baseUser.id, action: 'login' }),
      );
    });

    it('passes only the caregiver role to findByPhoneAndRoles for app=nursejobs', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ ...baseUser, code_hash: codeHash });
      await service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursejobs' });
      expect(usersRepo.findByPhoneAndRoles).toHaveBeenCalledWith(baseUser.phone, [UserRole.CAREGIVER]);
    });

    it('passes individual+organisation roles to findByPhoneAndRoles for app=nursenow', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({
        ...baseUser,
        role: UserRole.INDIVIDUAL,
        code_hash: codeHash,
      });
      await service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursenow' });
      expect(usersRepo.findByPhoneAndRoles).toHaveBeenCalledWith(baseUser.phone, [
        UserRole.INDIVIDUAL,
        UserRole.ORGANISATION,
      ]);
    });

    it('logs in an individual account, with no verification_status in the response', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({
        ...baseUser,
        role: UserRole.INDIVIDUAL,
        code_hash: codeHash,
      });
      const result = await service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursenow' });
      expect(result.user_id).toBe(baseUser.id);
      expect(result).not.toHaveProperty('verification_status');
      expect(caregiverProfilesRepo.findByUserId).not.toHaveBeenCalled();
    });

    it('logs in an organisation account, with no verification_status in the response', async () => {
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({
        ...baseUser,
        role: UserRole.ORGANISATION,
        code_hash: codeHash,
      });
      const result = await service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursenow' });
      expect(result.user_id).toBe(baseUser.id);
      expect(result).not.toHaveProperty('verification_status');
      expect(caregiverProfilesRepo.findByUserId).not.toHaveBeenCalled();
    });

    it('throws AUTH_002 when no account in the requested app bucket exists (e.g. an admin phone under app=nursejobs)', async () => {
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      await expect(
        service.loginCode({ phone: baseUser.phone, code: '1234', app: 'nursejobs' }),
      ).rejects.toMatchObject({ code: 'AUTH_002' });
    });
  });

  describe('loginOtp', () => {
    it('throws AUTH_011 for an invalid/expired token', async () => {
      tokenService.verifyPhoneVerificationToken.mockImplementation(() => {
        throw new Error('jwt expired');
      });
      await expect(
        service.loginOtp({ phone: baseUser.phone, app: 'nursejobs', phone_verification_token: 'bad' }),
      ).rejects.toMatchObject({ code: 'AUTH_011' });
    });

    it('throws AUTH_011 when the token purpose is register, not login (no cross-purpose replay)', async () => {
      tokenService.verifyPhoneVerificationToken.mockReturnValue({
        phone: baseUser.phone,
        app: 'nursejobs',
        purpose: 'register',
        type: 'phone_verification',
      });
      await expect(
        service.loginOtp({ phone: baseUser.phone, app: 'nursejobs', phone_verification_token: 'tok' }),
      ).rejects.toMatchObject({ code: 'AUTH_011' });
    });

    it('throws AUTH_002 when no account exists in the requested app bucket', async () => {
      tokenService.verifyPhoneVerificationToken.mockReturnValue({
        phone: baseUser.phone,
        app: 'nursejobs',
        purpose: 'login',
        type: 'phone_verification',
      });
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      await expect(
        service.loginOtp({ phone: baseUser.phone, app: 'nursejobs', phone_verification_token: 'tok' }),
      ).rejects.toMatchObject({ code: 'AUTH_002' });
    });

    it('succeeds for an account that has a PIN set (code_hash is never consulted)', async () => {
      tokenService.verifyPhoneVerificationToken.mockReturnValue({
        phone: baseUser.phone,
        app: 'nursejobs',
        purpose: 'login',
        type: 'phone_verification',
      });
      const codeHash = await bcrypt.hash('1234', 4);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ ...baseUser, code_hash: codeHash });
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ verification_status: VerificationStatus.AVAILABLE });

      const result = await service.loginOtp({
        phone: baseUser.phone,
        app: 'nursejobs',
        phone_verification_token: 'tok',
      });
      expect((result as { verification_status: string }).verification_status).toBe('available');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: baseUser.id, afterValue: expect.objectContaining({ method: 'otp' }) }),
      );
    });

    it('succeeds for an account with NO PIN set (code_hash null) — this is the revert-safety-net guarantee: an account registered while OTP mode was on can still log in via OTP even after OTP mode is later disabled, since this endpoint is never gated by the flag', async () => {
      tokenService.verifyPhoneVerificationToken.mockReturnValue({
        phone: baseUser.phone,
        app: 'nursejobs',
        purpose: 'login',
        type: 'phone_verification',
      });
      // otpAuthSettingsRepo defaults to { enabled: false } in beforeEach —
      // OTP mode is OFF here, yet loginOtp still succeeds.
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ ...baseUser, code_hash: null });
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ verification_status: VerificationStatus.AVAILABLE });

      const result = await service.loginOtp({
        phone: baseUser.phone,
        app: 'nursejobs',
        phone_verification_token: 'tok',
      });
      expect(result.user_id).toBe(baseUser.id);
      expect(otpAuthSettingsRepo.findByApp).not.toHaveBeenCalled();
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
