import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { ErrorLogsRepository } from '../database/repositories/error-logs.repository';
import { RequestStatsRepository } from '../database/repositories/request-stats.repository';
import { ListErrorLogsQueryDto } from './dto/list-error-logs-query.dto';

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
  ) {}

  async list(query: ListErrorLogsQueryDto) {
    const { items, total } = await this.errorLogsRepo.list({ page: query.page, limit: query.limit });
    return {
      data: items,
      meta: { page: query.page, limit: query.limit, total, totalPages: Math.ceil(total / query.limit) },
    };
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
