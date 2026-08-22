import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';
import { MyApplicationSummary } from './jobs.repository';

export interface OrganisationRequirementRecord {
  id: string;
  requirement_number: number;
  posted_by: string;
  type_of_nurse: string;
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
  status: string;
  rejection_reason: string | null;
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
  accommodation_provided: boolean;
  food_provided: boolean;
  special_skills: string | null;
  status: string;
}

export interface UpdateOrganisationRequirementInput {
  type_of_nurse: string;
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
         (posted_by, type_of_nurse, accommodation_provided, food_provided, special_skills, status)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [
        input.posted_by,
        input.type_of_nurse,
        input.accommodation_provided,
        input.food_provided,
        input.special_skills,
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
   *  the caregiver-facing browse list (no per-caregiver filtering yet,
   *  unlike GET /caregiver/jobs's preference filters). */
  async listActiveForCaregiver(profileId: string): Promise<OrganisationRequirementWithMyApplication[]> {
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
       WHERE r.status = 'active'
       ORDER BY r.posted_at DESC`,
      [profileId],
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
         frequency_of_care = $3,
         salary_amount = $4,
         schedule_type = $5,
         start_date = $6,
         end_date = $7,
         schedule_repeat = $8,
         specific_days = $9,
         accommodation_provided = $10,
         food_provided = $11,
         special_skills = $12,
         status = CASE WHEN $13::boolean THEN 'active' ELSE status END,
         posted_at = CASE WHEN $13::boolean THEN NOW() ELSE posted_at END,
         updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        id,
        input.type_of_nurse,
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
        input.activate ?? false,
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
}
