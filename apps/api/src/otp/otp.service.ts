import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { randomInt } from 'crypto';
import { Config, LoginFailureReason, OtpPurpose, Validation } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { OtpVerificationsRepository } from '../database/repositories/otp-verifications.repository';
import { TokenService } from '../auth/token.service';
import { Msg91Service } from './msg91.service';
import { LoginAttemptsService } from '../login-attempts/login-attempts.service';

@Injectable()
export class OtpService {
  constructor(
    private readonly otpVerificationsRepo: OtpVerificationsRepository,
    private readonly tokenService: TokenService,
    private readonly smsProvider: Msg91Service,
    private readonly loginAttempts: LoginAttemptsService,
  ) {}

  async send(phone: string, app: string, purpose: string): Promise<void> {
    const secondsSinceLast = await this.otpVerificationsRepo.secondsSinceLastSend(phone, app, purpose);
    if (secondsSinceLast !== null && secondsSinceLast < Validation.OTP_RESEND_COOLDOWN_SECONDS) {
      throw new AppException('GEN_004');
    }

    const recentCount = await this.otpVerificationsRepo.countRecentSends(
      phone,
      app,
      purpose,
      Validation.OTP_SEND_WINDOW_MINUTES,
    );
    if (recentCount >= Validation.OTP_MAX_SENDS_PER_WINDOW) {
      throw new AppException('GEN_004');
    }

    const otp = randomInt(0, 10 ** Validation.OTP_LENGTH)
      .toString()
      .padStart(Validation.OTP_LENGTH, '0');
    const otpHash = await bcrypt.hash(otp, Config.BCRYPT_SALT_ROUNDS);
    const expiresAt = new Date(Date.now() + Validation.OTP_EXPIRY_MINUTES * 60 * 1000);

    await this.otpVerificationsRepo.create(phone, app, purpose, otpHash, expiresAt);

    // Awaited, not fire-and-forget (unlike EmailService) — the user cannot
    // proceed without this actually being delivered, so a provider failure
    // must surface as an error rather than being swallowed.
    await this.smsProvider.sendOtp(phone, otp);
  }

  async verify(
    phone: string,
    app: string,
    purpose: string,
    otp: string,
    context: { ipAddress?: string | null; userAgent?: string | null } = {},
  ): Promise<string> {
    const row = await this.otpVerificationsRepo.findLatestActive(phone, app, purpose);
    if (!row) {
      this.recordLoginFailure(purpose, phone, app, LoginFailureReason.OTP_WRONG, context);
      throw new AppException('AUTH_012');
    }

    const matches = await bcrypt.compare(otp, row.otp_hash);
    if (!matches) {
      const updated = await this.otpVerificationsRepo.incrementAttempts(row.id);
      if (updated.attempts >= updated.max_attempts) {
        this.recordLoginFailure(purpose, phone, app, LoginFailureReason.OTP_LOCKED, context);
        throw new AppException('AUTH_013');
      }
      this.recordLoginFailure(purpose, phone, app, LoginFailureReason.OTP_WRONG, context);
      throw new AppException('AUTH_012');
    }

    await this.otpVerificationsRepo.markConsumed(row.id);
    return this.tokenService.signPhoneVerificationToken({ phone, app, purpose });
  }

  /** Only a *login* OTP that fails means someone couldn't get in — a failed
   *  registration OTP is a different story (no account yet). The identity is
   *  resolved from the phone when the report is read, so no user lookup here. */
  private recordLoginFailure(
    purpose: string,
    phone: string,
    app: string,
    reason: string,
    context: { ipAddress?: string | null; userAgent?: string | null },
  ): void {
    if (purpose !== OtpPurpose.LOGIN) return;
    this.loginAttempts.recordFailure({
      phone,
      app,
      method: 'otp',
      reason,
      userId: null,
      userRole: null,
      ipAddress: context.ipAddress ?? null,
      userAgent: context.userAgent ?? null,
    });
  }
}
