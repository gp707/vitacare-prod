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
  organisation_name: string | null;
  // Sanitized "what was the user doing" snapshot (migration 085) — see
  // sanitizeRequestContext for exactly what is kept/redacted.
  request_context: Record<string, unknown> | null;
  user_agent: string | null;
  status: ErrorLogStatus;
  resolved_at: Date | null;
  resolved_by: string | null;
  resolved_by_name: string | null;
  resolution_note: string | null;
}

export type ErrorLogStatus = 'open' | 'resolved';

/** One person who has hit unexpected errors, with the identity an admin
 *  needs to call them (name, phone, display-id numbers) and what happened
 *  last. */
export interface AffectedUserRecord {
  user_id: string;
  full_name: string;
  phone: string;
  role: string;
  caregiver_number: number | null;
  caregiver_profile_id: string | null;
  patient_number: number | null;
  org_number: number | null;
  organisation_name: string | null;
  error_count: number;
  open_count: number;
  last_error_at: Date;
  last_error_id: string;
  last_message: string;
  last_request: string;
}

export interface ListErrorLogsFilters {
  /** 'all' (default) applies no status filter. */
  status?: ErrorLogStatus | 'all';
  userId?: string;
  /** Case-insensitive match on path or message. */
  search?: string;
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
  requestContext?: Record<string, unknown> | null;
  userAgent?: string | null;
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
      `INSERT INTO error_logs
         (method, path, status_code, message, stack, user_id, user_role, ip_address, request_context, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [
        input.method,
        input.path,
        input.statusCode,
        input.message,
        input.stack,
        input.userId,
        input.userRole,
        input.ipAddress,
        input.requestContext ? JSON.stringify(input.requestContext) : null,
        input.userAgent ?? null,
      ],
    );
  }

  async list(page: ListPage, filters: ListErrorLogsFilters = {}): Promise<{ items: ErrorLogRecord[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const { clause, params } = this.buildWhereClause(filters);
    // The identity joins are only needed by the list query for display — the
    // WHERE clause only touches error_logs columns, so the count query can
    // stay a plain count over the one table.
    const [listResult, countResult] = await Promise.all([
      this.db.query<ErrorLogRecord>(
        `SELECT e.*, u.full_name AS user_full_name, u.phone AS user_phone,
                cp.caregiver_number, cp.id AS caregiver_profile_id,
                ip.patient_number, op.org_number, op.organisation_name,
                ru.full_name AS resolved_by_name
         FROM error_logs e
         LEFT JOIN users u ON u.id = e.user_id
         LEFT JOIN caregiver_profiles cp ON cp.user_id = e.user_id
         LEFT JOIN individual_profiles ip ON ip.user_id = e.user_id
         LEFT JOIN organisation_profiles op ON op.user_id = e.user_id
         LEFT JOIN users ru ON ru.id = e.resolved_by
         ${clause}
         ORDER BY e.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, page.limit, offset],
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM error_logs e ${clause}`, params),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Every person who has hit an unexpected error (most recent first), one
   *  row each — the "who do I call" view. Anonymous errors (no user) can't
   *  be called and are not included. [status] narrows which errors are
   *  counted: with 'open' a person whose errors were all handled drops off
   *  the list. */
  async listAffectedUsers(
    page: ListPage,
    status: ErrorLogStatus | 'all' = 'open',
  ): Promise<{ items: AffectedUserRecord[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const statusClause = status === 'all' ? '' : 'AND e.status = $1';
    const statusParams = status === 'all' ? [] : [status];
    const [listResult, countResult] = await Promise.all([
      this.db.query<{
        user_id: string;
        full_name: string;
        phone: string;
        role: string;
        caregiver_number: number | null;
        caregiver_profile_id: string | null;
        patient_number: number | null;
        org_number: number | null;
        organisation_name: string | null;
        error_count: string;
        open_count: string;
        last_error_at: Date;
        last_error_id: string;
        last_message: string;
        last_request: string;
      }>(
        `SELECT e.user_id, u.full_name, u.phone, u.role,
                cp.caregiver_number, cp.id AS caregiver_profile_id,
                ip.patient_number, op.org_number, op.organisation_name,
                COUNT(*) AS error_count,
                COUNT(*) FILTER (WHERE e.status = 'open') AS open_count,
                MAX(e.created_at) AS last_error_at,
                (ARRAY_AGG(e.id ORDER BY e.created_at DESC))[1] AS last_error_id,
                (ARRAY_AGG(e.message ORDER BY e.created_at DESC))[1] AS last_message,
                (ARRAY_AGG(e.method || ' ' || e.path ORDER BY e.created_at DESC))[1] AS last_request
         FROM error_logs e
         JOIN users u ON u.id = e.user_id
         LEFT JOIN caregiver_profiles cp ON cp.user_id = e.user_id
         LEFT JOIN individual_profiles ip ON ip.user_id = e.user_id
         LEFT JOIN organisation_profiles op ON op.user_id = e.user_id
         WHERE e.user_id IS NOT NULL ${statusClause}
         GROUP BY e.user_id, u.full_name, u.phone, u.role,
                  cp.caregiver_number, cp.id, ip.patient_number, op.org_number, op.organisation_name
         ORDER BY MAX(e.created_at) DESC
         LIMIT $${statusParams.length + 1} OFFSET $${statusParams.length + 2}`,
        [...statusParams, page.limit, offset],
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(DISTINCT e.user_id) FROM error_logs e WHERE e.user_id IS NOT NULL ${statusClause}`,
        statusParams,
      ),
    ]);
    return {
      total: Number(countResult.rows[0].count),
      items: listResult.rows.map((row) => ({
        ...row,
        error_count: Number(row.error_count),
        open_count: Number(row.open_count),
      })),
    };
  }

  async findById(id: string): Promise<{ id: string; user_id: string | null; status: ErrorLogStatus } | null> {
    const result = await this.db.query<{ id: string; user_id: string | null; status: ErrorLogStatus }>(
      'SELECT id, user_id, status FROM error_logs WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  /** Marks one error resolved. A no-op (returns false) if it was already
   *  resolved — the `status = 'open'` guard lives in the UPDATE itself so two
   *  admins resolving at once can't both "win". */
  async resolve(id: string, adminId: string, note: string | null): Promise<boolean> {
    const result = await this.db.query(
      `UPDATE error_logs
          SET status = 'resolved', resolved_at = NOW(), resolved_by = $2, resolution_note = $3
        WHERE id = $1 AND status = 'open'`,
      [id, adminId, note],
    );
    return (result.rowCount ?? 0) > 0;
  }

  /** "I called them" — resolves every still-open error for one person at
   *  once. Returns how many were resolved. */
  async resolveAllForUser(userId: string, adminId: string, note: string | null): Promise<number> {
    const result = await this.db.query(
      `UPDATE error_logs
          SET status = 'resolved', resolved_at = NOW(), resolved_by = $2, resolution_note = $3
        WHERE user_id = $1 AND status = 'open'`,
      [userId, adminId, note],
    );
    return result.rowCount ?? 0;
  }

  private buildWhereClause(filters: ListErrorLogsFilters): { clause: string; params: unknown[] } {
    const conditions: string[] = [];
    const params: unknown[] = [];
    if (filters.status && filters.status !== 'all') {
      params.push(filters.status);
      conditions.push(`e.status = $${params.length}`);
    }
    if (filters.userId) {
      params.push(filters.userId);
      conditions.push(`e.user_id = $${params.length}`);
    }
    if (filters.search) {
      params.push(`%${filters.search}%`);
      conditions.push(`(e.path ILIKE $${params.length} OR e.message ILIKE $${params.length})`);
    }
    return { clause: conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '', params };
  }

  /** Used by the daily retention sweep (ErrorLogRetentionService). Returns
   *  the number of rows actually removed, same convention as
   *  AuditLogsRepository.deleteOlderThan. */
  async deleteOlderThan(cutoff: Date): Promise<number> {
    const result = await this.db.query('DELETE FROM error_logs WHERE created_at < $1', [cutoff]);
    return result.rowCount ?? 0;
  }
}
