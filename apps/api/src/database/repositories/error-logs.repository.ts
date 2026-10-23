import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface ErrorLogRecord {
  id: string;
  method: string;
  path: string;
  status_code: number;
  message: string;
  stack: string | null;
  user_id: string | null;
  user_role: string | null;
  ip_address: string | null;
  created_at: Date;
}

export interface CreateErrorLogInput {
  method: string;
  path: string;
  statusCode: number;
  message: string;
  stack: string | null;
  userId: string | null;
  userRole: string | null;
  ipAddress: string | null;
}

export interface ListPage {
  page: number;
  limit: number;
}

/** Backing store for GlobalExceptionFilter's catch-all branch — see
 *  migration 082's comment for exactly which errors land here (genuinely
 *  unexpected ones only, never an already-categorized AppException/
 *  HttpException). Rows older than the retention window are purged daily
 *  by ErrorLogRetentionService, not here. */
@Injectable()
export class ErrorLogsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Never awaited by the caller (GlobalExceptionFilter fires this and
   *  moves on) — a logging failure must never affect the response already
   *  being sent back to the client. Errors from this call are swallowed by
   *  the caller, not here, so this stays a plain, testable insert. */
  async create(input: CreateErrorLogInput): Promise<void> {
    await this.db.query(
      `INSERT INTO error_logs (method, path, status_code, message, stack, user_id, user_role, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        input.method,
        input.path,
        input.statusCode,
        input.message,
        input.stack,
        input.userId,
        input.userRole,
        input.ipAddress,
      ],
    );
  }

  async list(page: ListPage): Promise<{ items: ErrorLogRecord[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<ErrorLogRecord>(
        `SELECT * FROM error_logs ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
        [page.limit, offset],
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM error_logs`),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Used by the daily retention sweep (ErrorLogRetentionService). Returns
   *  the number of rows actually removed, same convention as
   *  AuditLogsRepository.deleteOlderThan. */
  async deleteOlderThan(cutoff: Date): Promise<number> {
    const result = await this.db.query('DELETE FROM error_logs WHERE created_at < $1', [cutoff]);
    return result.rowCount ?? 0;
  }
}
