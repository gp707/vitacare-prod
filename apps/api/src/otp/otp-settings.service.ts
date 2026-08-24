import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { OtpAuthSettingsRepository } from '../database/repositories/otp-auth-settings.repository';

@Injectable()
export class OtpSettingsService {
  constructor(
    private readonly otpAuthSettingsRepo: OtpAuthSettingsRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — called by both mobile apps before rendering registration/
   *  login UI. An unrecognized app 404s rather than silently passing,
   *  same reasoning as AppConfigService.checkVersion. */
  async isEnabled(app: string): Promise<{ enabled: boolean }> {
    const row = await this.otpAuthSettingsRepo.findByApp(app);
    if (!row) throw new AppException('GEN_002');
    return { enabled: row.enabled };
  }

  adminList() {
    return this.otpAuthSettingsRepo.findAll();
  }

  async adminUpdate(adminId: string, app: string, enabled: boolean, ipAddress: string | null) {
    const existing = await this.otpAuthSettingsRepo.findByApp(app);
    if (!existing) throw new AppException('GEN_002');

    const updated = await this.otpAuthSettingsRepo.update(app, enabled, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.OTP_SETTING_UPDATED,
      entityType: 'otp_auth_settings',
      beforeValue: { app, enabled: existing.enabled },
      afterValue: { app, enabled },
      ipAddress,
    });

    return updated;
  }
}
