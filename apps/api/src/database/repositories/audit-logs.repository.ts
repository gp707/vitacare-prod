import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface AuditLogListItem {
  id: string;
  user_id: string | null;
  user_name: string | null;
  target_user_id: string | null;
  target_user_name: string | null;
  action: AuditAction;
  entity_type: string;
  entity_id: string | null;
  before_value: Record<string, unknown> | null;
  after_value: Record<string, unknown> | null;
  ip_address: string | null;
  created_at: Date;
  // Resolved so admin-web can link to the job instead of a bare
  // entity_type/entity_id UUID — the only two entity_types this applies
  // to are 'jobs' (entity_id is the job itself) and 'job_applications'
  // (entity_id is the application; resolved one hop further via
  // job_applications.job_id). Every other entity_type (e.g.
  // caregiver_profiles, app_min_versions) leaves all three null.
  // admin_job_number/patient_job_number back the "ADMIN-JOB-<n>"/
  // "PAT-JOB-<n>" display id (migration 047) — exactly one is non-null,
  // matching whichever role posted the job.
  admin_job_number: number | null;
  patient_job_number: number | null;
  job_id: string | null;
  // The target user's own role and display-id-backing number — lets
  // admin-web render "NUR-<n>"/"PAT-<n>"/"ORG-<n>" next to the target's
  // name instead of just the bare name. target_user_role is null when
  // there's no target_user_id at all (e.g. a job/organisation_requirement
  // create, which has no single "affected user"). Exactly one of
  // target_caregiver_number/target_patient_number/target_org_number is
  // ever non-null, matching target_user_role — a user has exactly one
  // role, so at most one of the three profile-table joins can match.
  target_user_role: string | null;
  target_caregiver_number: number | null;
  target_patient_number: number | null;
  target_org_number: number | null;
  // Resolved the same way as job_id above, but for
  // organisation_requirements — 'organisation_requirements' entries
  // resolve directly (entity_id is the requirement),
  // 'organisation_requirement_applications' entries resolve one hop
  // further via .requirement_id. Every other entity_type leaves both
  // null. requirement_number backs the "ORG-JOB-<n>" display id.
  requirement_number: number | null;
  requirement_id: string | null;
}

export interface AuditLogListFilters {
  userId?: string;
  targetUserId?: string;
  jobId?: string;
  requirementId?: string;
  action?: AuditAction;
  fromDate?: string;
  toDate?: string;
  search?: string;
}

export interface AuditLogListSort {
  order: 'asc' | 'desc';
  page: number;
  limit: number;
}

function buildWhereClause(filters: AuditLogListFilters): { clause: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.userId) {
    params.push(filters.userId);
    conditions.push(`al.user_id = $${params.length}`);
  }
  if (filters.targetUserId) {
    // Matches either side of the entry, not just target_user_id. A
    // caregiver's own self-service actions (apply/reapply/complete) log
    // with user_id = the caregiver and no target_user_id at all (there's
    // no "other party" for a caregiver acting on their own application);
    // only a decision someone else makes ABOUT that caregiver (admin's or
    // an individual's/organisation's accept/reject) sets target_user_id =
    // the caregiver. A strict target_user_id match therefore showed only
    // half of a caregiver's own history (decisions made about them, never
    // their own applies/reapplies/closes) on CaregiverDetailScreen's Audit
    // History tab. Broadening to an OR is safe: this filter is never
    // exposed as a manual textbox in the general Audit Logs screen, only
    // passed programmatically from a caregiver/individual/organisation
    // detail screen's own "View full audit log" link, where "everything
    // involving this account" is exactly the intent either way.
    params.push(filters.targetUserId);
    conditions.push(`(al.user_id = $${params.length} OR al.target_user_id = $${params.length})`);
  }
  if (filters.jobId) {
    params.push(filters.jobId);
    conditions.push(`COALESCE(job_direct.id, job_via_app.id) = $${params.length}`);
  }
  if (filters.requirementId) {
    params.push(filters.requirementId);
    conditions.push(`COALESCE(org_req_direct.id, org_req_via_app.id) = $${params.length}`);
  }
  if (filters.action) {
    params.push(filters.action);
    conditions.push(`al.action = $${params.length}`);
  }
  if (filters.fromDate) {
    params.push(filters.fromDate);
    conditions.push(`al.created_at >= $${params.length}`);
  }
  if (filters.toDate) {
    params.push(filters.toDate);
    conditions.push(`al.created_at <= $${params.length}::date + INTERVAL '1 day'`);
  }
  // Matches ANY of: actor name/phone, target name/phone, target's own
  // display id, the entry's entity_type, or the affected job/requirement's
  // display id — one search box covering everything an admin might already
  // know about the entry they're looking for. Reuses the same param
  // placeholder for every branch of the OR (identical %term% value), so
  // this only ever costs one entry in params regardless of how many
  // columns it's matched against.
  if (filters.search) {
    params.push(`%${filters.search}%`);
    const p = params.length;
    conditions.push(`(
      actor.full_name ILIKE $${p} OR
      actor.phone ILIKE $${p} OR
      target.full_name ILIKE $${p} OR
      target.phone ILIKE $${p} OR
      ('NUR-' || target_cp.caregiver_number::text) ILIKE $${p} OR
      ('PAT-' || target_ip.patient_number::text) ILIKE $${p} OR
      ('ORG-' || target_op.org_number::text) ILIKE $${p} OR
      al.entity_type ILIKE $${p} OR
      ('ADMIN-JOB-' || COALESCE(job_direct.admin_job_number, job_via_app.admin_job_number)::text) ILIKE $${p} OR
      ('PAT-JOB-' || COALESCE(job_direct.patient_job_number, job_via_app.patient_job_number)::text) ILIKE $${p} OR
      ('ORG-JOB-' || COALESCE(org_req_direct.requirement_number, org_req_via_app.requirement_number)::text) ILIKE $${p}
    )`);
  }

  return {
    clause: conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '',
    params,
  };
}

// Shared by both the list query and the count query — a search-filter
// condition references these joined tables' columns (actor/target names,
// display-id-backing numbers, job/requirement numbers), so both queries
// need the exact same JOINs or the count query 500s at runtime the moment
// a search term is supplied. See CLAUDE.md's admin-web filters note on
// this exact gotcha.
const AUDIT_LOG_JOINS = `
  LEFT JOIN users actor ON actor.id = al.user_id
  LEFT JOIN users target ON target.id = al.target_user_id
  LEFT JOIN caregiver_profiles target_cp ON target_cp.user_id = al.target_user_id
  LEFT JOIN individual_profiles target_ip ON target_ip.user_id = al.target_user_id
  LEFT JOIN organisation_profiles target_op ON target_op.user_id = al.target_user_id
  LEFT JOIN jobs job_direct ON al.entity_type = 'jobs' AND job_direct.id = al.entity_id
  LEFT JOIN job_applications ja ON al.entity_type = 'job_applications' AND ja.id = al.entity_id
  LEFT JOIN jobs job_via_app ON job_via_app.id = ja.job_id
  LEFT JOIN organisation_requirements org_req_direct
    ON al.entity_type = 'organisation_requirements' AND org_req_direct.id = al.entity_id
  LEFT JOIN organisation_requirement_applications ora
    ON al.entity_type = 'organisation_requirement_applications' AND ora.id = al.entity_id
  LEFT JOIN organisation_requirements org_req_via_app ON org_req_via_app.id = ora.requirement_id
`;

@Injectable()
export class AuditLogsRepository {
  constructor(private readonly db: DatabaseService) {}

  async list(
    filters: AuditLogListFilters,
    sort: AuditLogListSort,
  ): Promise<{ items: AuditLogListItem[]; total: number }> {
    const { clause, params } = buildWhereClause(filters);
    const orderDirection = sort.order === 'asc' ? 'ASC' : 'DESC';
    const offset = (sort.page - 1) * sort.limit;

    const listParams = [...params, sort.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<AuditLogListItem>(
        `SELECT al.id, al.user_id, actor.full_name AS user_name,
                al.target_user_id, target.full_name AS target_user_name,
                al.action, al.entity_type, al.entity_id,
                al.before_value, al.after_value, al.ip_address, al.created_at,
                COALESCE(job_direct.admin_job_number, job_via_app.admin_job_number) AS admin_job_number,
                COALESCE(job_direct.patient_job_number, job_via_app.patient_job_number) AS patient_job_number,
                COALESCE(job_direct.id, job_via_app.id) AS job_id,
                target.role AS target_user_role,
                target_cp.caregiver_number AS target_caregiver_number,
                target_ip.patient_number AS target_patient_number,
                target_op.org_number AS target_org_number,
                COALESCE(org_req_direct.requirement_number, org_req_via_app.requirement_number) AS requirement_number,
                COALESCE(org_req_direct.id, org_req_via_app.id) AS requirement_id
         FROM audit_logs al
         ${AUDIT_LOG_JOINS}
         ${clause}
         ORDER BY al.created_at ${orderDirection}
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM audit_logs al ${AUDIT_LOG_JOINS} ${clause}`,
        params,
      ),
    ]);

    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Hard-deletes every row older than [cutoff] — the retention sweep's
   *  actual delete, called by AuditLogRetentionService.purgeExpiredLogs().
   *  Returns the count deleted so the caller can decide whether it's worth
   *  audit-logging the sweep itself (skipped when nothing was deleted, to
   *  avoid writing a no-op row every single day — see that service). */
  async deleteOlderThan(cutoff: Date): Promise<number> {
    const result = await this.db.query('DELETE FROM audit_logs WHERE created_at < $1', [cutoff]);
    return result.rowCount ?? 0;
  }
}
