import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AuditService } from '../audit/audit.service';
import { JobSettingsRepository } from '../database/repositories/job-settings.repository';
import { UpdateJobSettingsDto } from './dto/update-job-settings.dto';

@Injectable()
export class JobSettingsService {
  constructor(
    private readonly jobSettingsRepo: JobSettingsRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — every app that shows the caregiver-facing apply-by urgency
   *  badge (currently just caregiver-app) fetches this once (e.g. at
   *  splash) rather than assuming the old hardcoded 3-day constant. */
  get() {
    return this.jobSettingsRepo.find();
  }

  adminGet() {
    return this.jobSettingsRepo.findWithUpdater();
  }

  async adminUpdate(adminId: string, dto: UpdateJobSettingsDto, ipAddress: string | null) {
    const existing = await this.jobSettingsRepo.find();
    const updated = await this.jobSettingsRepo.update(dto.apply_by_window_days, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOB_SETTINGS_UPDATED,
      entityType: 'job_settings',
      beforeValue: { apply_by_window_days: existing.apply_by_window_days },
      afterValue: { apply_by_window_days: dto.apply_by_window_days },
      ipAddress,
    });

    return updated;
  }
}
