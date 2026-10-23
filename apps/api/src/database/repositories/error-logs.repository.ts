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
  // Resolved via a LEFT JOIN on users/caregiver_profiles/individual_profiles/
  // organisation_profiles, same pattern as AuditLogsRepository's own target
  // resolution — so admin-web can show who actually hit this error (name,
  // phone, NUR-/PAT-/ORG-<n> display id), not just a bare user_id UUID.
  // Only populated by list(), not create() (which never reads these back).
  user_full_name: string | null;
  user_phone: string | null;
  caregiver_number: number | null;
  caregiver_profile_id: string | null;
  patient_number: number | null;
  org_number: number | null;
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
        `SELECT e.*, u.full_name AS user_full_name, u.phone AS user_phone,
                cp.caregiver_number, cp.id AS caregiver_profile_id,
                ip.patient_number, op.org_number
         FROM error_logs e
         LEFT JOIN users u ON u.id = e.user_id
         LEFT JOIN caregiver_profiles cp ON cp.user_id = e.user_id
         LEFT JOIN individual_profiles ip ON ip.user_id = e.user_id
         LEFT JOIN organisation_profiles op ON op.user_id = e.user_id
         ORDER BY e.created_at DESC LIMIT $1 OFFSET $2`,
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
