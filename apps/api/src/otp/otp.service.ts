import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { randomInt } from 'crypto';
import { Config, Validation } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { OtpVerificationsRepository } from '../database/repositories/otp-verifications.repository';
import { TokenService } from '../auth/token.service';
import { Msg91Service } from './msg91.service';

@Injectable()
export class OtpService {
  constructor(
    private readonly otpVerificationsRepo: OtpVerificationsRepository,
    private readonly tokenService: TokenService,
    private readonly smsProvider: Msg91Service,
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

  async verify(phone: string, app: string, purpose: string, otp: string): Promise<string> {
    const row = await this.otpVerificationsRepo.findLatestActive(phone, app, purpose);
    if (!row) {
      throw new AppException('AUTH_012');
    }

    const matches = await bcrypt.compare(otp, row.otp_hash);
    if (!matches) {
      const updated = await this.otpVerificationsRepo.incrementAttempts(row.id);
      if (updated.attempts >= updated.max_attempts) {
        throw new AppException('AUTH_013');
      }
      throw new AppException('AUTH_012');
    }

    await this.otpVerificationsRepo.markConsumed(row.id);
    return this.tokenService.signPhoneVerificationToken({ phone, app, purpose });
  }
}
