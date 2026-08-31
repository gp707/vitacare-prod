import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { randomUUID } from 'crypto';
import { AuditAction, Config, LoginApp, OtpPurpose, UserRole, VerificationStatus } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { UsersRepository, UserRecord } from '../database/repositories/users.repository';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { CaregiverLanguagesRepository } from '../database/repositories/caregiver-languages.repository';
import { IndividualProfilesRepository } from '../database/repositories/individual-profiles.repository';
import { OrganisationProfilesRepository } from '../database/repositories/organisation-profiles.repository';
import { RefreshTokensRepository } from '../database/repositories/refresh-tokens.repository';
import { OtpAuthSettingsRepository } from '../database/repositories/otp-auth-settings.repository';
import { DatabaseService } from '../database/database.service';
import { EmailService } from '../email/email.service';
import { AuditService } from '../audit/audit.service';
import { TokenService } from './token.service';
import { RefreshTokenPayload } from '../common/interfaces/jwt-payload.interface';
import { RegisterDto } from './dto/register.dto';
import { RegisterIndividualDto } from './dto/register-individual.dto';
import { RegisterOrganisationDto } from './dto/register-organisation.dto';
import { LoginCodeDto } from './dto/login-code.dto';
import { LoginOtpDto } from './dto/login-otp.dto';
import { LoginEmailDto } from './dto/login-email.dto';

// Caregiver and both NurseNow account types (individual, organisation) log
// in with phone + a bcrypt-hashed 4-digit code — same mechanism, different
// profile table created at registration. Which roles are searched depends
// on the caller's LoginApp (phone is unique per app bucket, not globally
// — see migration 045).
const CODE_LOGIN_ROLES_BY_APP: Record<string, UserRole[]> = {
  [LoginApp.NURSEJOBS]: [UserRole.CAREGIVER],
  [LoginApp.NURSENOW]: [UserRole.INDIVIDUAL, UserRole.ORGANISATION],
};

export interface IssuedTokens {
  access_token: string;
  refresh_token: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly db: DatabaseService,
    private readonly usersRepo: UsersRepository,
    private readonly caregiverProfilesRepo: CaregiverProfilesRepository,
    private readonly caregiverLanguagesRepo: CaregiverLanguagesRepository,
    private readonly individualProfilesRepo: IndividualProfilesRepository,
    private readonly organisationProfilesRepo: OrganisationProfilesRepository,
    private readonly refreshTokensRepo: RefreshTokensRepository,
    private readonly otpAuthSettingsRepo: OtpAuthSettingsRepository,
    private readonly tokenService: TokenService,
    private readonly emailService: EmailService,
    private readonly auditService: AuditService,
  ) {}

  async register(dto: RegisterDto, ipAddress: string | null = null) {
    const existing = await this.usersRepo.findByPhoneAndRoles(dto.phone, [UserRole.CAREGIVER]);
    if (existing) {
      throw new AppException('AUTH_001');
    }

    const { codeHash } = await this.resolveCredential(LoginApp.NURSEJOBS, dto, OtpPurpose.REGISTER, dto.phone);

    const { user, profile } = await this.db.withTransaction(async (client) => {
      const userResult = await client.query<UserRecord>(
        `INSERT INTO users (phone, full_name, role, code_hash) VALUES ($1, $2, $3, $4) RETURNING *`,
        [dto.phone, dto.full_name, UserRole.CAREGIVER, codeHash],
      );
      const user = userResult.rows[0];

      const profile = await this.caregiverProfilesRepo.create(
        {
          user_id: user.id,
          gender: dto.gender,
          age: dto.age,
          religion: dto.religion,
          highest_qualification: dto.highest_qualification,
          terms_accepted: dto.terms_accepted,
        },
        client,
      );

      await this.caregiverLanguagesRepo.createMany(profile.id, dto.languages, client);

      return { user, profile };
    });

    const tokens = await this.issueTokens(user);

    void this.emailService.sendToAdmin(
      'New caregiver registration',
      `${dto.full_name} (${dto.phone}) just registered and is pending office call verification.`,
    );

    await this.auditService.log({
      userId: user.id,
      action: AuditAction.REGISTRATION,
      entityType: 'users',
      entityId: user.id,
      afterValue: {
        full_name: dto.full_name,
        phone: dto.phone,
        gender: dto.gender,
        age: dto.age,
        religion: dto.religion,
        highest_qualification: dto.highest_qualification,
      },
      ipAddress,
    });

    return {
      user_id: user.id,
      profile_id: profile.id,
      ...tokens,
      verification_status: profile.verification_status,
    };
  }

  async loginCode(dto: LoginCodeDto, ipAddress: string | null = null) {
    const roles = CODE_LOGIN_ROLES_BY_APP[dto.app];
    const user = await this.usersRepo.findByPhoneAndRoles(dto.phone, roles);
    if (!user) {
      throw new AppException('AUTH_002');
    }
    if (!user.is_active) {
      throw new AppException('AUTH_004');
    }
    if (!user.code_hash || !(await bcrypt.compare(dto.code, user.code_hash))) {
      throw new AppException('AUTH_008');
    }

    return this.finishLogin(user, ipAddress, 'code');
  }

  /** Proves phone ownership via a phone-verification-token (issued by
   *  POST /auth/otp/verify, purpose 'login') instead of a PIN — reuses
   *  findByPhoneAndRoles' same role-bucket lookup, so it works identically
   *  for an account that has a PIN and one that doesn't (code_hash is
   *  never consulted here at all). Deliberately NOT gated by the
   *  otp_auth_settings flag — this stays callable even if OTP mode is
   *  later disabled, so an account that registered while it was on (and so
   *  has no PIN) is never locked out. */
  async loginOtp(dto: LoginOtpDto, ipAddress: string | null = null) {
    this.verifyPhoneToken(dto.phone_verification_token, dto.phone, dto.app, OtpPurpose.LOGIN);

    const roles = CODE_LOGIN_ROLES_BY_APP[dto.app];
    const user = await this.usersRepo.findByPhoneAndRoles(dto.phone, roles);
    if (!user) {
      throw new AppException('AUTH_002');
    }
    if (!user.is_active) {
      throw new AppException('AUTH_004');
    }

    return this.finishLogin(user, ipAddress, 'otp');
  }

  private async finishLogin(user: UserRecord, ipAddress: string | null, method: 'code' | 'otp') {
    await this.refreshTokensRepo.pruneStaleForUser(user.id);
    const tokens = await this.issueTokens(user);

    await this.auditService.log({
      userId: user.id,
      action: AuditAction.LOGIN,
      entityType: 'users',
      entityId: user.id,
      afterValue: { timestamp: new Date().toISOString(), method },
      ipAddress,
    });

    // verification_status is a caregiver-only concept (the 5-state
    // pending_call/available/... pipeline) — individual/organisation
    // accounts have no such workflow, so it's simply omitted rather than
    // defaulted to a caregiver status that wouldn't mean anything for them.
    if (user.role === UserRole.INDIVIDUAL || user.role === UserRole.ORGANISATION) {
      return { user_id: user.id, ...tokens };
    }

    const profile = await this.caregiverProfilesRepo.findByUserId(user.id);
    return {
      user_id: user.id,
      ...tokens,
      verification_status: profile?.verification_status ?? VerificationStatus.PENDING_CALL,
    };
  }

  /** Individual (patient/family) registration — deliberately minimal
   *  compared to caregiver registration: no gender/age/religion/
   *  qualification, no documents, no verification pipeline. Logs in the
   *  same way (phone + code) immediately after. */
  async registerIndividual(dto: RegisterIndividualDto, ipAddress: string | null = null) {
    const existing = await this.usersRepo.findByPhoneAndRoles(dto.phone, [
      UserRole.INDIVIDUAL,
      UserRole.ORGANISATION,
    ]);
    if (existing) {
      throw new AppException('AUTH_001');
    }

    const { codeHash } = await this.resolveCredential(LoginApp.NURSENOW, dto, OtpPurpose.REGISTER, dto.phone);

    const user = await this.db.withTransaction(async (client) => {
      const userResult = await client.query<UserRecord>(
        `INSERT INTO users (phone, full_name, role, code_hash) VALUES ($1, $2, $3, $4) RETURNING *`,
        [dto.phone, dto.full_name, UserRole.INDIVIDUAL, codeHash],
      );
      const user = userResult.rows[0];
      await this.individualProfilesRepo.create(user.id, dto.terms_accepted, client);
      return user;
    });

    const tokens = await this.issueTokens(user);

    await this.auditService.log({
      userId: user.id,
      action: AuditAction.REGISTRATION,
      entityType: 'users',
      entityId: user.id,
      afterValue: { full_name: dto.full_name, phone: dto.phone, role: UserRole.INDIVIDUAL },
      ipAddress,
    });

    return { user_id: user.id, ...tokens };
  }

  /** Organisation (hospital/rehab/clinic) registration — like individual,
   *  no account-level approval gate, logs in the same way immediately
   *  after. Unlike individual, collects identity/location fields up front
   *  since every requirement it later posts inherits city/area from here
   *  (no per-requirement location — see "NurseNow" in CLAUDE.md). */
  async registerOrganisation(dto: RegisterOrganisationDto, ipAddress: string | null = null) {
    const existing = await this.usersRepo.findByPhoneAndRoles(dto.phone, [
      UserRole.INDIVIDUAL,
      UserRole.ORGANISATION,
    ]);
    if (existing) {
      throw new AppException('AUTH_001');
    }

    const { codeHash } = await this.resolveCredential(LoginApp.NURSENOW, dto, OtpPurpose.REGISTER, dto.phone);

    const user = await this.db.withTransaction(async (client) => {
      const userResult = await client.query<UserRecord>(
        `INSERT INTO users (phone, full_name, role, code_hash) VALUES ($1, $2, $3, $4) RETURNING *`,
        [dto.phone, dto.contact_person_name, UserRole.ORGANISATION, codeHash],
      );
      const user = userResult.rows[0];
      await this.organisationProfilesRepo.create(
        user.id,
        {
          organisation_name: dto.organisation_name,
          contact_person_name: dto.contact_person_name,
          organisation_type: dto.organisation_type,
          city: dto.city,
          area: dto.area,
          terms_accepted: dto.terms_accepted,
        },
        client,
      );
      return user;
    });

    const tokens = await this.issueTokens(user);

    await this.auditService.log({
      userId: user.id,
      action: AuditAction.REGISTRATION,
      entityType: 'users',
      entityId: user.id,
      afterValue: {
        organisation_name: dto.organisation_name,
        contact_person_name: dto.contact_person_name,
        phone: dto.phone,
        role: UserRole.ORGANISATION,
      },
      ipAddress,
    });

    return { user_id: user.id, ...tokens };
  }

  async loginEmail(dto: LoginEmailDto, ipAddress: string | null = null) {
    const user = await this.usersRepo.findByEmail(dto.email);
    if (!user || (user.role !== UserRole.ADMIN && user.role !== UserRole.SUPER_ADMIN)) {
      throw new AppException('AUTH_003');
    }
    if (!user.is_active) {
      throw new AppException('AUTH_004');
    }
    if (!user.password_hash || !(await bcrypt.compare(dto.password, user.password_hash))) {
      throw new AppException('AUTH_003');
    }

    await this.refreshTokensRepo.pruneStaleForUser(user.id);
    const tokens = await this.issueTokens(user);

    await this.auditService.log({
      userId: user.id,
      action: AuditAction.LOGIN,
      entityType: 'users',
      entityId: user.id,
      afterValue: { timestamp: new Date().toISOString(), method: 'email' },
      ipAddress,
    });

    return {
      user_id: user.id,
      ...tokens,
      // Not applicable to admin accounts (no caregiver_profiles row).
      verification_status: null,
    };
  }

  async refresh(refreshToken: string) {
    let payload: RefreshTokenPayload;
    try {
      payload = this.tokenService.verifyRefreshToken(refreshToken);
    } catch {
      throw new AppException('AUTH_006');
    }
    if (payload.type !== 'refresh') {
      throw new AppException('AUTH_006');
    }

    const record = await this.refreshTokensRepo.findActiveById(payload.jti);
    if (!record || record.user_id !== payload.sub) {
      throw new AppException('AUTH_006');
    }
    const matches = await bcrypt.compare(refreshToken, record.token_hash);
    if (!matches) {
      throw new AppException('AUTH_006');
    }

    const user = await this.usersRepo.findById(payload.sub);
    if (!user || !user.is_active) {
      throw new AppException('AUTH_006');
    }

    await this.refreshTokensRepo.revoke(record.id);
    const tokens = await this.issueTokens(user);
    return tokens;
  }

  async logout(userId: string): Promise<void> {
    await this.refreshTokensRepo.revokeAllForUser(userId);
  }

  /** Picks the credential path for a registration: PIN (today's default)
   *  or OTP-verified phone token, based on the LIVE otp_auth_settings flag
   *  for that app — read server-side, never trusted from the request body,
   *  so a client can't bypass an admin's toggle by simply sending a `code`
   *  anyway. */
  private async resolveCredential(
    app: string,
    dto: { code?: string; phone_verification_token?: string },
    purpose: string,
    phone: string,
  ): Promise<{ codeHash: string | null }> {
    const setting = await this.otpAuthSettingsRepo.findByApp(app);
    const otpEnabled = setting?.enabled ?? false;

    if (otpEnabled) {
      if (!dto.phone_verification_token) {
        throw new AppException('AUTH_010');
      }
      this.verifyPhoneToken(dto.phone_verification_token, phone, app, purpose);
      return { codeHash: null };
    }

    if (!dto.code) {
      throw new AppException('AUTH_009');
    }
    const codeHash = await bcrypt.hash(dto.code, Config.BCRYPT_SALT_ROUNDS);
    return { codeHash };
  }

  /** Throws AUTH_011 for anything wrong with the token — expired, bad
   *  signature, or a mismatch on phone/app/purpose (e.g. a 'register'
   *  token replayed against login, or one issued for a different phone/
   *  app than the request claims). */
  private verifyPhoneToken(token: string, phone: string, app: string, purpose: string): void {
    let payload;
    try {
      payload = this.tokenService.verifyPhoneVerificationToken(token);
    } catch {
      throw new AppException('AUTH_011');
    }
    if (
      payload.type !== 'phone_verification' ||
      payload.phone !== phone ||
      payload.app !== app ||
      payload.purpose !== purpose
    ) {
      throw new AppException('AUTH_011');
    }
  }

  private async issueTokens(user: {
    id: string;
    role: UserRole;
    phone: string;
  }): Promise<IssuedTokens> {
    const access_token = this.tokenService.signAccessToken(user);

    const tokenRowId = randomUUID();
    const { token: refresh_token, expiresAt } = this.tokenService.signRefreshToken(
      user.id,
      tokenRowId,
    );
    const tokenHash = await bcrypt.hash(refresh_token, Config.BCRYPT_SALT_ROUNDS);
    await this.refreshTokensRepo.create(tokenRowId, user.id, tokenHash, expiresAt);

    return { access_token, refresh_token };
  }
}
