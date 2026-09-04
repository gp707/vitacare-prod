import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { AuditAction } from '@vitacare/shared-constants';
import { AuditService } from '../audit/audit.service';
import { AuditLogRetentionRepository } from '../database/repositories/audit-log-retention.repository';
import { AuditLogsRepository } from '../database/repositories/audit-logs.repository';
import { UpdateAuditLogRetentionDto } from './dto/update-audit-log-retention.dto';

@Injectable()
export class AuditLogRetentionService {
  private readonly logger = new Logger(AuditLogRetentionService.name);

  constructor(
    private readonly retentionRepo: AuditLogRetentionRepository,
    private readonly auditLogsRepo: AuditLogsRepository,
    private readonly auditService: AuditService,
  ) {}

  adminGet() {
    return this.retentionRepo.findWithUpdater();
  }

  async adminUpdate(adminId: string, dto: UpdateAuditLogRetentionDto, ipAddress: string | null) {
    const existing = await this.retentionRepo.find();
    const updated = await this.retentionRepo.update(dto.retention_days, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.AUDIT_LOG_RETENTION_UPDATED,
      entityType: 'audit_log_retention_settings',
      beforeValue: { retention_days: existing.retention_days },
      afterValue: { retention_days: dto.retention_days },
      ipAddress,
    });

    return updated;
  }

  /** Daily sweep, offset from FcmService's own 8 AM IST job to avoid both
   *  running at once. Reads the current admin-configured window on every
   *  run (not a value cached at startup), so a same-day retention_days
   *  change takes effect on the very next run. Deliberately a hard delete,
   *  no export/backup step (confirmed with the user) — this is the entire
   *  mechanism, there is no separate manual "archive now" trigger. */
  @Cron('0 3 * * *', { timeZone: 'Asia/Kolkata' })
  async purgeExpiredLogs(): Promise<void> {
    const { retention_days: retentionDays } = await this.retentionRepo.find();
    const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000);

    const deletedCount = await this.auditLogsRepo.deleteOlderThan(cutoff);
    if (deletedCount === 0) return;

    this.logger.log(`Purged ${deletedCount} audit_logs row(s) older than ${cutoff.toISOString()}`);

    // Skipped when nothing was deleted (the common case on most days) —
    // logging a no-op entry every day would itself work against the whole
    // point of this feature (bounding audit_logs' growth).
    await this.auditService.log({
      userId: null,
      action: AuditAction.AUDIT_LOGS_PURGED,
      entityType: 'audit_logs',
      afterValue: { deleted_count: deletedCount, retention_days: retentionDays, cutoff: cutoff.toISOString() },
      ipAddress: null,
    });
  }
}
