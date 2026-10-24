import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { ErrorLogsRepository } from '../database/repositories/error-logs.repository';
import { RequestStatsRepository } from '../database/repositories/request-stats.repository';
import { ListErrorLogsQueryDto } from './dto/list-error-logs-query.dto';
import { ListAffectedUsersQueryDto } from './dto/list-affected-users-query.dto';

/** Hardcoded, not admin-configurable (unlike AuditLogRetentionService's own
 *  window) — the user explicitly asked for a fixed 7-day rolling window
 *  for this one, no settings screen needed. */
const RETENTION_DAYS = 7;

@Injectable()
export class ErrorLogsService {
  private readonly logger = new Logger(ErrorLogsService.name);

  constructor(
    private readonly errorLogsRepo: ErrorLogsRepository,
    private readonly requestStatsRepo: RequestStatsRepository,
    private readonly auditService: AuditService,
  ) {}

  async list(query: ListErrorLogsQueryDto) {
    const { items, total } = await this.errorLogsRepo.list(
      { page: query.page, limit: query.limit },
      { status: query.status, userId: query.user_id, search: query.search },
    );
    return {
      data: items,
      meta: { page: query.page, limit: query.limit, total, totalPages: Math.ceil(total / query.limit) },
    };
  }

  /** Everyone who has hit an unexpected error, one row each, with the
   *  identity needed to call them — see ErrorLogsRepository.listAffectedUsers. */
  async listAffectedUsers(query: ListAffectedUsersQueryDto) {
    const { items, total } = await this.errorLogsRepo.listAffectedUsers(
      { page: query.page, limit: query.limit },
      query.status,
    );
    return {
      data: items,
      meta: { page: query.page, limit: query.limit, total, totalPages: Math.ceil(total / query.limit) },
    };
  }

  /** Marks one error handled. Idempotent: resolving an already-resolved
   *  error is a no-op (no second audit entry), not an error. */
  async resolve(id: string, adminId: string, note: string | undefined, ipAddress: string | null) {
    const existing = await this.errorLogsRepo.findById(id);
    if (!existing) throw new AppException('GEN_002');

    const resolved = await this.errorLogsRepo.resolve(id, adminId, note ?? null);
    if (resolved) {
      await this.auditService.log({
        userId: adminId,
        targetUserId: existing.user_id ?? undefined,
        action: AuditAction.ERROR_LOG_RESOLVED,
        entityType: 'error_logs',
        entityId: id,
        afterValue: { note: note ?? null },
        ipAddress,
      });
    }
    return { message: resolved ? 'Error marked resolved' : 'Error was already resolved' };
  }

  /** "I called them" — resolves every open error for one person in one go. */
  async resolveAllForUser(userId: string, adminId: string, note: string | undefined, ipAddress: string | null) {
    const count = await this.errorLogsRepo.resolveAllForUser(userId, adminId, note ?? null);
    if (count > 0) {
      await this.auditService.log({
        userId: adminId,
        targetUserId: userId,
        action: AuditAction.ERROR_LOG_RESOLVED,
        entityType: 'error_logs',
        afterValue: { note: note ?? null, resolved_count: count },
        ipAddress,
      });
    }
    return { resolved_count: count };
  }

  /** Daily request/error counts for the last [days] calendar days
   *  (including today) — admin-web sums these for a "last N days" summary
   *  and reads the last entry for "today". A day with zero traffic has no
   *  row at all (see RequestStatsRepository.listLastDays). */
  async getStats(days: number) {
    return this.requestStatsRepo.listLastDays(days);
  }

  /** Mirrors AuditLogRetentionService.purgeExpiredLogs's shape, fixed at
   *  RETENTION_DAYS instead of an admin-configured value. Offset to 3:15
   *  AM IST (vs audit logs' 3:00 AM) purely so the two sweeps don't both
   *  start in the same instant. */
  @Cron('15 3 * * *', { timeZone: 'Asia/Kolkata' })
  async purgeExpiredLogs(): Promise<void> {
    const cutoff = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const deletedCount = await this.errorLogsRepo.deleteOlderThan(cutoff);
    if (deletedCount === 0) return;
    this.logger.log(`Purged ${deletedCount} error_logs row(s) older than ${cutoff.toISOString()}`);
  }
}
