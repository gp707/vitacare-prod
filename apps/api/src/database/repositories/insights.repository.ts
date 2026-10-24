import { Injectable } from '@nestjs/common';
import { QueryResultRow } from 'pg';
import { DatabaseService } from '../database.service';

/** Who an Insights row is about — same identity resolution as Error Logs /
 *  Audit Logs / Tickets (LEFT JOIN all three profile tables; a user has
 *  exactly one role, so at most one of the three display-id numbers is
 *  non-null). admin-web renders `NUR-`/`PAT-`/`ORG-<n>` from these and
 *  links to the right detail screen via `role`. */
export interface InsightAccount {
  user_id: string;
  full_name: string;
  phone: string;
  role: string;
  created_at: Date;
  last_seen_at: Date | null;
  caregiver_number: number | null;
  caregiver_profile_id: string | null;
  verification_status: string | null;
  patient_number: number | null;
  org_number: number | null;
  organisation_name: string | null;
}

export interface PosterWithoutAcceptedRecord extends InsightAccount {
  postings: number;
  applicants: number;
  pending_applicants: number;
  first_applied_at: Date | null;
}

/** One phone number that has had failed logins — the person to call. */
export interface LoginProblemRecord {
  phone: string;
  attempts: number;
  wrong_pin_attempts: number;
  first_attempt_at: Date;
  last_attempt_at: Date;
  last_reason: string;
  last_app: string;
  /** 'locked_out' until they get in (or register); then 'recovered'. */
  status: 'locked_out' | 'recovered';
  // The account behind the number, when there is one (null for a number that
  // has no account at all — a mistyped or never-registered phone).
  user_id: string | null;
  full_name: string | null;
  role: string | null;
  is_active: boolean | null;
  created_at: Date | null;
  last_seen_at: Date | null;
  caregiver_number: number | null;
  caregiver_profile_id: string | null;
  patient_number: number | null;
  org_number: number | null;
  organisation_name: string | null;
}

export interface Page<T> {
  items: T[];
  total: number;
}

export interface PageParams {
  page: number;
  limit: number;
}

/** The three registration-facing roles. Admins are staff, not "users of the
 *  app", so every Insights report excludes them. */
const APP_ROLES_SQL = `u.role IN ('caregiver', 'individual', 'organisation')`;

const ACCOUNT_COLUMNS = `
  u.id AS user_id, u.full_name, u.phone, u.role, u.created_at, u.last_seen_at,
  cp.caregiver_number, cp.id AS caregiver_profile_id, cp.verification_status,
  ip.patient_number, op.org_number, op.organisation_name`;

const ACCOUNT_JOINS = `
  LEFT JOIN caregiver_profiles cp ON cp.user_id = u.id
  LEFT JOIN individual_profiles ip ON ip.user_id = u.id
  LEFT JOIN organisation_profiles op ON op.user_id = u.id`;

/** Read-only queries behind the admin "Insights" screen. Every list
 *  returns `{ items, total }` (paged) so admin-web can show "N of M".
 *  Reports that depend on `users.last_seen_at` are only as accurate as that
 *  column — see migration 084 for how it is maintained and backfilled. */
@Injectable()
export class InsightsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Accounts whose last authenticated request was within the last
   *  [hours]. Most recently active first. */
  async listActiveUsers(params: PageParams & { hours: number; role?: string }): Promise<Page<InsightAccount>> {
    const values: unknown[] = [params.hours];
    let roleClause = '';
    if (params.role) {
      values.push(params.role);
      roleClause = `AND u.role = $${values.length}`;
    }
    const from = `
      FROM users u ${ACCOUNT_JOINS}
      WHERE ${APP_ROLES_SQL} AND u.deleted_at IS NULL
        AND u.last_seen_at >= NOW() - ($1::int * INTERVAL '1 hour') ${roleClause}`;
    return this.page<InsightAccount>(ACCOUNT_COLUMNS, from, values, 'u.last_seen_at DESC', params);
  }

  /** Accounts registered at least [minAgeHours] ago that never came back:
   *  their last activity is still (within a few minutes of) the registration
   *  itself. Oldest registrations first — those are the longest-lost. */
  async listInactiveSinceRegistration(
    params: PageParams & { minAgeHours: number; role?: string },
  ): Promise<Page<InsightAccount>> {
    const values: unknown[] = [params.minAgeHours];
    let roleClause = '';
    if (params.role) {
      values.push(params.role);
      roleClause = `AND u.role = $${values.length}`;
    }
    const from = `
      FROM users u ${ACCOUNT_JOINS}
      WHERE ${APP_ROLES_SQL} AND u.deleted_at IS NULL
        AND u.created_at <= NOW() - ($1::int * INTERVAL '1 hour')
        AND (u.last_seen_at IS NULL OR u.last_seen_at <= u.created_at + INTERVAL '10 minutes') ${roleClause}`;
    return this.page<InsightAccount>(ACCOUNT_COLUMNS, from, values, 'u.created_at ASC', params);
  }

  /** Patients/families and organisations that have received applicants but
   *  never accepted any (no application of theirs is `accepted` or
   *  `completed`). Longest-waiting first. Requirements with zero applicants
   *  are deliberately not listed — that's "nobody applied", a different
   *  problem from "candidates applied and were never picked". */
  async listPostersWithoutAccepted(params: PageParams): Promise<Page<PosterWithoutAcceptedRecord>> {
    const stats = `
      SELECT user_id, postings, applicants, pending_applicants, first_applied_at FROM (
        SELECT j.posted_by AS user_id,
               COUNT(DISTINCT j.id) AS postings,
               COUNT(a.id) AS applicants,
               COUNT(a.id) FILTER (WHERE a.status = 'applied') AS pending_applicants,
               MIN(COALESCE(a.applied_at, a.created_at)) AS first_applied_at
          FROM jobs j
          JOIN job_applications a ON a.job_id = j.id
         GROUP BY j.posted_by
        HAVING COUNT(a.id) FILTER (WHERE a.status IN ('accepted', 'completed')) = 0
        UNION ALL
        SELECT r.posted_by AS user_id,
               COUNT(DISTINCT r.id) AS postings,
               COUNT(a.id) AS applicants,
               COUNT(a.id) FILTER (WHERE a.status = 'applied') AS pending_applicants,
               MIN(COALESCE(a.applied_at, a.created_at)) AS first_applied_at
          FROM organisation_requirements r
          JOIN organisation_requirement_applications a ON a.requirement_id = r.id
         GROUP BY r.posted_by
        HAVING COUNT(a.id) FILTER (WHERE a.status IN ('accepted', 'completed')) = 0
      ) combined`;
    const columns = `${ACCOUNT_COLUMNS}, s.postings, s.applicants, s.pending_applicants, s.first_applied_at`;
    const from = `
      FROM (${stats}) s
      JOIN users u ON u.id = s.user_id ${ACCOUNT_JOINS}
      WHERE u.deleted_at IS NULL`;
    const page = await this.page<Record<string, unknown>>(columns, from, [], 's.first_applied_at ASC', params);
    return {
      total: page.total,
      items: page.items.map((row) => ({
        ...(row as unknown as InsightAccount),
        postings: Number(row.postings),
        applicants: Number(row.applicants),
        pending_applicants: Number(row.pending_applicants),
        first_applied_at: (row.first_applied_at as Date | null) ?? null,
      })),
    };
  }

  /** Caregivers who have never applied to anything — neither a regular job
   *  nor an organisation requirement. Longest-registered first. */
  async listCaregiversNeverApplied(params: PageParams): Promise<Page<InsightAccount>> {
    const from = `
      FROM users u ${ACCOUNT_JOINS}
      WHERE u.role = 'caregiver' AND u.deleted_at IS NULL AND cp.id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM job_applications ja WHERE ja.profile_id = cp.id)
        AND NOT EXISTS (SELECT 1 FROM organisation_requirement_applications oa WHERE oa.profile_id = cp.id)`;
    return this.page<InsightAccount>(ACCOUNT_COLUMNS, from, [], 'u.created_at ASC', params);
  }

  /** Phone numbers with failed logins in the last [days], most recent first —
   *  with the account behind each number and whether the person has since
   *  got in. "Got in" = any activity or a successful login after their last
   *  failure, or (for a number that had no account) registering afterwards.
   *  [status] 'locked_out' (default) is the follow-up list: people still stuck. */
  async listLoginProblems(
    params: PageParams & { days: number; status: 'locked_out' | 'recovered' | 'all' },
  ): Promise<Page<LoginProblemRecord>> {
    // LATERAL + LIMIT 1: a number can (for legacy dual-registered accounts)
    // match more than one app account — show one row per phone, preferring
    // the most recently active account.
    const from = `
      FROM (
        SELECT f.*, u.id AS user_id, u.full_name, u.role, u.is_active, u.created_at, u.last_seen_at,
               cp.caregiver_number, cp.id AS caregiver_profile_id,
               ip.patient_number, op.org_number, op.organisation_name,
               -- COALESCE: last_seen_at can be NULL, and a NULL here would make
               -- "NOT recovered" NULL too and silently drop the row from the list.
               (u.id IS NOT NULL AND (
                  COALESCE(u.last_seen_at > f.last_attempt_at, FALSE)
                  OR u.created_at > f.last_attempt_at
                  OR EXISTS (SELECT 1 FROM audit_logs a
                              WHERE a.user_id = u.id AND a.action = 'login' AND a.created_at > f.last_attempt_at)
               )) AS recovered
          FROM (
            SELECT phone,
                   COUNT(*) AS attempts,
                   COUNT(*) FILTER (WHERE reason = 'wrong_pin') AS wrong_pin_attempts,
                   MIN(created_at) AS first_attempt_at,
                   MAX(created_at) AS last_attempt_at,
                   (ARRAY_AGG(reason ORDER BY created_at DESC))[1] AS last_reason,
                   (ARRAY_AGG(app ORDER BY created_at DESC))[1] AS last_app
              FROM login_attempts
             WHERE created_at >= NOW() - ($1::int * INTERVAL '1 day')
             GROUP BY phone
          ) f
          LEFT JOIN LATERAL (
            SELECT * FROM users u2
             WHERE u2.phone = f.phone AND ${APP_ROLES_SQL.replace(/u\./g, 'u2.')} AND u2.deleted_at IS NULL
             ORDER BY u2.last_seen_at DESC NULLS LAST
             LIMIT 1
          ) u ON TRUE
          LEFT JOIN caregiver_profiles cp ON cp.user_id = u.id
          LEFT JOIN individual_profiles ip ON ip.user_id = u.id
          LEFT JOIN organisation_profiles op ON op.user_id = u.id
      ) p
      WHERE ${params.status === 'all' ? 'TRUE' : params.status === 'recovered' ? 'p.recovered' : 'NOT p.recovered'}`;
    const columns = `p.*, CASE WHEN p.recovered THEN 'recovered' ELSE 'locked_out' END AS status`;
    const page = await this.page<Record<string, unknown>>(columns, from, [params.days], 'p.last_attempt_at DESC', params);
    return {
      total: page.total,
      items: page.items.map((row) => ({
        ...(row as unknown as LoginProblemRecord),
        attempts: Number(row.attempts),
        wrong_pin_attempts: Number(row.wrong_pin_attempts),
      })),
    };
  }

  /** Runs the list query and its matching count query from the same
   *  FROM/WHERE text — a filter added to one must be in the other, which is
   *  exactly the bug class CLAUDE.md warns about for hand-written count
   *  queries, so both are built from the single `from` string here. */
  private async page<T extends QueryResultRow>(
    columns: string,
    from: string,
    values: unknown[],
    orderBy: string,
    params: PageParams,
  ): Promise<Page<T>> {
    const offset = (params.page - 1) * params.limit;
    const [list, count] = await Promise.all([
      this.db.query<T>(`SELECT ${columns} ${from} ORDER BY ${orderBy} LIMIT $${values.length + 1} OFFSET $${values.length + 2}`, [
        ...values,
        params.limit,
        offset,
      ]),
      this.db.query<{ count: string }>(`SELECT COUNT(*) ${from}`, values),
    ]);
    return { items: list.rows, total: Number(count.rows[0].count) };
  }
}
