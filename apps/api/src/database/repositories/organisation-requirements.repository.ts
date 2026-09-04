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
  frequency_of_care: string | null;
  salary_amount: number | null;
  /** Admin-set scheduling — exactly one of two modes, picked via
   *  schedule_type. date_range uses start_date/end_date; specific_days
   *  uses schedule_repeat + specific_days (weekdays 1-7 if weekly,
   *  days-of-month 1-31 if monthly). Null until approved. Organisation-
   *  only — regular jobs keep a single start_date. */
  schedule_type: string | null;
  start_date: string | null;
  end_date: string | null;
  schedule_repeat: string | null;
  specific_days: number[] | null;
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  /** Org-set at creation, 1-49, defaults to 1 — how many caregivers this
   *  one requirement is looking to fill. */
  number_of_vacancies: number;
  /** Org-set at creation. Null = no preference. Mirrors jobs.preferred_gender
   *  exactly (including excluding 'other' as a preference value). */
  preferred_gender: string | null;
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

/** GET /caregiver/organisation-requirements' shape — mirrors
 *  JobWithMyApplication's per-caregiver my_application join, so
 *  caregiver-app's merged Jobs list can render "already applied" state
 *  identically for both jobs and organisation requirements. */
export interface OrganisationRequirementWithMyApplication extends OrganisationRequirementWithOrg {
  my_application: MyApplicationSummary | null;
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
  status: string;
}

/** Every field the org self-edit endpoint can touch — the org-owned subset
 *  of a requirement's fields, same set as CreateOrganisationRequirementInput
 *  minus posted_by/status. See OrganisationRequirementsRepository.updateOwnFields. */
export interface UpdateOwnOrganisationRequirementInput {
  type_of_nurse: string;
  type_of_nurse_other: string | null;
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  number_of_vacancies: number;
  preferred_gender: string | null;
}

export interface UpdateOrganisationRequirementInput {
  type_of_nurse: string;
  type_of_nurse_other: string | null;
  frequency_of_care: string | null;
  salary_amount: number | null;
  schedule_type: string | null;
  start_date: string | null;
  end_date: string | null;
  schedule_repeat: string | null;
  specific_days: number[] | null;
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  number_of_vacancies: number;
  preferred_gender: string | null;
  /** Only passed when approving a pending_review requirement — activates
   *  it and stamps posted_at, same repost semantics as JobsRepository. */
  activate?: boolean;
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
          special_skills, number_of_vacancies, preferred_gender, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
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
        input.status,
      ],
    );
    return result.rows[0];
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
         CASE WHEN ora.id IS NULL THEN NULL ELSE jsonb_build_object(
           'status', ora.status,
           'applied_at', ora.applied_at,
           'accepted_at', ora.accepted_at,
           'rejected_at', ora.rejected_at,
           'completed_at', ora.completed_at,
           'decided_by_admin', ora.decided_by IS NOT NULL,
           'decline_reason', ora.decline_reason
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
  ): Promise<{ items: OrganisationRequirementWithOrg[]; total: number }> {
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
      this.db.query<OrganisationRequirementWithOrg>(
        `SELECT r.*, op.organisation_name, op.organisation_type, op.city, op.area
         FROM organisation_requirements r
         JOIN organisation_profiles op ON op.user_id = r.posted_by
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

  /** Full edit — same shape/validation as create. If [activate] is set
   *  (admin approving a pending_review requirement, or reposting a closed
   *  one), status flips to active and posted_at is bumped to NOW(). */
  async update(
    id: string,
    input: UpdateOrganisationRequirementInput,
    client?: PoolClient,
  ): Promise<OrganisationRequirementRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<OrganisationRequirementRecord>(
      `UPDATE organisation_requirements SET
         type_of_nurse = $2,
         type_of_nurse_other = $3,
         frequency_of_care = $4,
         salary_amount = $5,
         schedule_type = $6,
         start_date = $7,
         end_date = $8,
         schedule_repeat = $9,
         specific_days = $10,
         accommodation_provided = $11,
         food_provided = $12,
         special_skills = $13,
         number_of_vacancies = $14,
         preferred_gender = $15,
         status = CASE WHEN $16::boolean THEN 'active' ELSE status END,
         posted_at = CASE WHEN $16::boolean THEN NOW() ELSE posted_at END,
         updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        id,
        input.type_of_nurse,
        input.type_of_nurse_other,
        input.frequency_of_care,
        input.salary_amount,
        input.schedule_type,
        input.start_date,
        input.end_date,
        input.schedule_repeat,
        input.specific_days,
        input.accommodation_provided,
        input.food_provided,
        input.special_skills,
        input.number_of_vacancies,
        input.preferred_gender,
        input.activate ?? false,
      ],
    );
    return result.rows[0];
  }

  /** The org's own self-edit — only the org-owned fields, never status/
   *  posted_at/frequency/salary/schedule (those stay admin-only). Mirrors
   *  JobsRepository/IndividualService's own self-edit not touching status. */
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

  async close(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirements SET status = 'closed', updated_at = NOW() WHERE id = $1`,
      [id],
    );
  }

  async reopen(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirements SET status = 'active', updated_at = NOW() WHERE id = $1`,
      [id],
    );
  }

  /** Org self-cancel — mirrors JobsRepository.cancel exactly (migration 048's
   *  cancelled_at column, org-requirement counterpart). */
  async cancel(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE organisation_requirements SET status = 'closed', cancelled_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [id],
    );
  }
}
