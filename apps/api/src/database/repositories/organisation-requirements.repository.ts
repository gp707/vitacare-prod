import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';
import { MyApplicationSummary } from './jobs.repository';

export interface OrganisationRequirementRecord {
  id: string;
  requirement_number: number;
  posted_by: string;
  type_of_nurse: string;
  /** Free text elaboration, only ever non-null when type_of_nurse is
   *  'others' — mirrors care_receivers.medical_condition_other. */
  type_of_nurse_other: string | null;
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  /** Org-set at creation, 1-49, defaults to 1 — how many caregivers this
   *  one requirement is looking to fill. */
  number_of_vacancies: number;
  /** Org-set at creation. Null = no preference. Mirrors jobs.preferred_gender
   *  exactly (including excluding 'other' as a preference value). */
  preferred_gender: string | null;
  /** Org-set at creation — 'short_term' or 'long_term'. See
   *  RequirementDuration in shared-constants. */
  duration_type: string | null;
  status: string;
  rejection_reason: string | null;
  /** Mirrors jobs.cancelled_at (migration 048) — set by the org's own
   *  self-cancel endpoint (OrganisationRequirementsService.cancelRequirement),
   *  never by admin's reject (that uses rejection_reason instead). */
  cancelled_at: Date | null;
  posted_at: Date;
  created_at: Date;
  updated_at: Date;
}

/** Joined with organisation_profiles — every requirement inherits its
 *  posting org's identity/location, there's no per-requirement city/area. */
export interface OrganisationRequirementWithOrg extends OrganisationRequirementRecord {
  organisation_name: string;
  organisation_type: string;
  city: string;
  area: string;
}

/** listForAdmin's shape — adds the org's own contact person name and phone
 *  (via a users join) so admin-web can show who to call about this
 *  requirement without a second round trip, mirroring
 *  JobListItemForAdmin's posted_by_name/posted_by_phone. */
export interface OrganisationRequirementListItemForAdmin extends OrganisationRequirementWithOrg {
  contact_person_name: string;
  organisation_phone: string;
}

/** GET /caregiver/organisation-requirements' shape — mirrors
 *  JobWithMyApplication's per-caregiver my_application join, so
 *  caregiver-app's merged Jobs list can render "already applied" state
 *  identically for both jobs and organisation requirements. */
export interface OrganisationRequirementWithMyApplication extends OrganisationRequirementWithOrg {
  my_application: MyApplicationSummary | null;
  /** Total distinct caregivers who have ever applied (any status — one row
   *  per caregiver per requirement via the upsert) — shown to every
   *  browsing caregiver as a plain "N applied" count, same convention as
   *  JobsRepository.listActiveForCaregiver's own applicant_count. Only
   *  populated by listActiveForCaregiver below. */
  applicant_count?: number;
}

export interface CreateOrganisationRequirementInput {
  posted_by: string;
  type_of_nurse: string;
  type_of_nurse_other: string | null;
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  number_of_vacancies: number;
  preferred_gender: string | null;
  duration_type: string;
  status: string;
}

/** Every field the org self-edit endpoint can touch — the org-owned subset
 *  of a requirement's fields, same set as CreateOrganisationRequirementInput
 *  minus posted_by/status. See OrganisationRequirementsRepository.updateOwnFields.
 *  This is every field there is — admin owns none of them; admin's entire
 *  role is a pure approve/reject click (see activate() below). */
export interface UpdateOwnOrganisationRequirementInput {
  type_of_nurse: string;
  type_of_nurse_other: string | null;
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  number_of_vacancies: number;
  preferred_gender: string | null;
  duration_type: string;
}

export interface ListOrganisationRequirementsFilters {
  status?: string;
  posted_by?: string;
  organisation_type?: string;
  city?: string;
  /** Matches the organisation's name or the requirement's display id
   *  (ORG-JOB-<n>) / raw requirement_number. */
  search?: string;
}

export interface ListPage {
  page: number;
  limit: number;
}

@Injectable()
export class OrganisationRequirementsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(
    input: CreateOrganisationRequirementInput,
    client?: PoolClient,
  ): Promise<OrganisationRequirementRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<OrganisationRequirementRecord>(
      `INSERT INTO organisation_requirements
         (posted_by, type_of_nurse, type_of_nurse_other, accommodation_provided, food_provided,
          special_skills, number_of_vacancies, preferred_gender, duration_type, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING *`,
      [
        input.posted_by,
        input.type_of_nurse,
        input.type_of_nurse_other,
        input.accommodation_provided,
        input.food_provided,
        input.special_skills,
        input.number_of_vacancies,
        input.preferred_gender,
        input.duration_type,
        input.status,
      ],
    );
    return result.rows[0];
  }

  /** Requirements awaiting admin's legitimacy review. Feeds the dashboard's
   *  "Needs Approval" tile alongside JobsRepository.countPendingApproval. */
  async countPendingApproval(): Promise<number> {
    const result = await this.db.query<{ count: string }>(
      `SELECT COUNT(*) FROM organisation_requirements WHERE status = 'pending_review'`,
    );
    return Number(result.rows[0].count);
  }

  async findById(id: string): Promise<OrganisationRequirementRecord | null> {
    const result = await this.db.query<OrganisationRequirementRecord>(
      'SELECT * FROM organisation_requirements WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  async listByPostedBy(postedBy: string): Promise<OrganisationRequirementRecord[]> {
    const result = await this.db.query<OrganisationRequirementRecord>(
      'SELECT * FROM organisation_requirements WHERE posted_by = $1 ORDER BY created_at DESC',
      [postedBy],
    );
    return result.rows;
  }

  /** Every active requirement, joined with its org's identity/location —
   *  the caregiver-facing browse list. [gender] mirrors
   *  JobsRepository.listActiveForCaregiver's own preferred_gender
   *  enforcement exactly: a requirement with no preference (NULL) is
   *  visible to everyone, one with a preference is only visible to a
   *  caregiver whose own gender matches. */
  async listActiveForCaregiver(
    profileId: string,
    gender: string,
  ): Promise<OrganisationRequirementWithMyApplication[]> {
    const result = await this.db.query<OrganisationRequirementWithMyApplication>(
      `SELECT r.*, op.organisation_name, op.organisation_type, op.city, op.area,
         (SELECT COUNT(*)::int FROM organisation_requirement_applications ora2
            WHERE ora2.requirement_id = r.id) AS applicant_count,
         CASE WHEN ora.id IS NULL THEN NULL ELSE jsonb_build_object(
           'status', ora.status,
           'applied_at', ora.applied_at,
           'accepted_at', ora.accepted_at,
           'rejected_at', ora.rejected_at,
           'completed_at', ora.completed_at,
           'reapplied_at', ora.reapplied_at,
           'decided_by_admin', ora.decided_by IS NOT NULL,
           'decline_reason', ora.decline_reason,
           'close_reason', ora.close_reason
         ) END AS my_application
       FROM organisation_requirements r
       JOIN organisation_profiles op ON op.user_id = r.posted_by
       LEFT JOIN organisation_requirement_applications ora ON ora.requirement_id = r.id AND ora.profile_id = $1
       WHERE r.status = 'active' AND (r.preferred_gender IS NULL OR r.preferred_gender = $2)
       ORDER BY r.posted_at DESC`,
      [profileId, gender],
    );
    return result.rows;
  }

  async listForAdmin(
    filters: ListOrganisationRequirementsFilters,
    page: ListPage,
  ): Promise<{ items: OrganisationRequirementListItemForAdmin[]; total: number }> {
    const conditions: string[] = [];
    const params: unknown[] = [];
    if (filters.status) {
      params.push(filters.status);
      conditions.push(`r.status = $${params.length}`);
    }
    if (filters.posted_by) {
      params.push(filters.posted_by);
      conditions.push(`r.posted_by = $${params.length}`);
    }
    if (filters.organisation_type) {
      params.push(filters.organisation_type);
      conditions.push(`op.organisation_type = $${params.length}`);
    }
    if (filters.city) {
      params.push(filters.city);
      conditions.push(`op.city = $${params.length}`);
    }
    if (filters.search) {
      params.push(`%${filters.search}%`);
      conditions.push(
        `(op.organisation_name ILIKE $${params.length} OR ('ORG-JOB-' || r.requirement_number::text) ILIKE $${params.length})`,
      );
    }
    const clause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];

    const [listResult, countResult] = await Promise.all([
      this.db.query<OrganisationRequirementListItemForAdmin>(
        `SELECT r.*, op.organisation_name, op.organisation_type, op.city, op.area,
                op.contact_person_name, u.phone AS organisation_phone
         FROM organisation_requirements r
         JOIN organisation_profiles op ON op.user_id = r.posted_by
         JOIN users u ON u.id = r.posted_by
         ${clause}
         ORDER BY r.created_at DESC
         LIMIT $${listParams.length - 1} OFFSET $${listParams.length}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM organisation_requirements r
         JOIN organisation_profiles op ON op.user_id = r.posted_by
         ${clause}`,
        params,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Flips a requirement live and bumps posted_at — used both by admin's
   *  approve (from pending_review or any closed requirement) and by the
   *  org's own self-service reactivate (from a requirement it previously
   *  cancelled). Clears cancelled_at/rejection_reason unconditionally: once
   *  active, a requirement is neither cancelled nor rejected, regardless of
   *  which closed state it's coming from. */
  async activate(id: string, client?: PoolClient): Promise<OrganisationRequirementRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<OrganisationRequirementRecord>(
      `UPDATE organisation_requirements
       SET status = 'active', cancelled_at = NULL, rejection_reason = NULL, posted_at = NOW(), updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [id],
    );
    return result.rows[0];
  }

  /** The org's own self-edit — every field there is, since admin owns
   *  none of them. Never touches status/posted_at. */
  async updateOwnFields(
    id: string,
    input: UpdateOwnOrganisationRequirementInput,
    client?: PoolClient,
  ): Promise<OrganisationRequirementRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<OrganisationRequirementRecord>(
      `UPDATE organisation_requirements SET
         type_of_nurse = $2,
         type_of_nurse_other = $3,
         accommodation_provided = $4,
         food_provided = $5,
         special_skills = $6,
         number_of_vacancies = $7,
         preferred_gender = $8,
         duration_type = $9,
         updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        id,
        input.type_of_nurse,
        input.type_of_nurse_other,
        input.accommodation_provided,
        input.food_provided,
        input.special_skills,
        input.number_of_vacancies,
        input.preferred_gender,
        input.duration_type,
      ],
    );
    return result.rows[0];
  }

  async reject(id: string, reason: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirements SET status = 'closed', rejection_reason = $2, updated_at = NOW() WHERE id = $1`,
      [id, reason],
    );
  }

  /** Org self-cancel — mirrors JobsRepository.cancel exactly (migration 048's
   *  cancelled_at column, org-requirement counterpart). Deliberately does
   *  NOT touch any application row — see OrganisationRequirementsService.
   *  cancelRequirement for why. */
  async cancel(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirements SET status = 'closed', cancelled_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [id],
    );
  }

  /** Applications that will disappear (via organisation_requirement_applications
   *  .requirement_id's own ON DELETE CASCADE) the moment these requirements
   *  are deleted — counted beforehand purely so the caller can report/
   *  audit-log an accurate number. Mirrors JobsRepository.countApplicationsForJobs. */
  async countApplicationsForRequirements(ids: string[], client?: PoolClient): Promise<number> {
    if (ids.length === 0) return 0;
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<{ count: string }>(
      'SELECT COUNT(*) FROM organisation_requirement_applications WHERE requirement_id = ANY($1::uuid[])',
      [ids],
    );
    return Number(result.rows[0].count);
  }

  /** Permanently deletes every requirement in [ids] — applications cascade-
   *  delete automatically (ON DELETE CASCADE). Unlike jobs, organisation
   *  requirements have no care_receiver equivalent to clean up afterward.
   *  Silently ignores any id that no longer exists. Must be called inside
   *  a transaction (see AdminBulkDeleteService). */
  async bulkDelete(ids: string[], client: PoolClient): Promise<OrganisationRequirementRecord[]> {
    if (ids.length === 0) return [];
    const result = await client.query<OrganisationRequirementRecord>(
      'DELETE FROM organisation_requirements WHERE id = ANY($1::uuid[]) RETURNING *',
      [ids],
    );
    return result.rows;
  }
}
