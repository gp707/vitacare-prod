import { Injectable } from '@nestjs/common';
import {
  City,
  DutyType,
  FrequencyOfCare,
  JobApplicationStatus,
  JobStatus,
  Language,
} from '@vitacare/shared-constants';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';
import { CareReceiverRecord } from './care-receivers.repository';

export interface JobRecord {
  id: string;
  job_number: number;
  care_receiver_id: string;
  city: City;
  area: string | null;
  description: string | null;
  duty_type: DutyType;
  frequency_of_care: FrequencyOfCare;
  start_time: string | null;
  end_time: string | null;
  start_date: string | null;
  languages: Language[];
  salary_amount: number | null;
  preferred_gender: string | null;
  preferred_religion: string | null;
  status: JobStatus;
  posted_by: string;
  /** Effective "went live" timestamp — starts equal to created_at, bumped
   *  to NOW() only when a closed job is edited-and-reposted. The 3-day
   *  apply-by urgency window is always computed from this, not created_at. */
  posted_at: Date;
  created_at: Date;
  updated_at: Date;
}

/** The caregiver's own application to this job, if any — includes the
 *  real per-transition timeline (not just the current status) so the
 *  caregiver-app can show what actually happened and when, e.g.
 *  "Applied: ... / Accepted: ... / Declined by employer: ..." instead of
 *  a bare "You declined" that can't tell a self-decline apart from an
 *  admin undoing a prior acceptance. */
export interface MyApplicationSummary {
  status: JobApplicationStatus;
  applied_at: Date | null;
  accepted_at: Date | null;
  rejected_at: Date | null;
  completed_at: Date | null;
  decided_by_admin: boolean;
}

export interface JobWithMyApplication extends JobRecord {
  my_application: MyApplicationSummary | null;
  /** Full care-needs description, joined in so caregiver-app can show
   *  About Patient / About Patient Condition details on the jobs list
   *  itself, without a second per-job request. */
  care_receiver: CareReceiverRecord;
}

/** A job the caregiver is (or was) accepted onto — GET /caregiver/jobs/assigned's
 *  shape. Unlike JobWithMyApplication, my_application is never null here (the
 *  query only returns rows the caregiver has an accepted/completed
 *  application for), and the posting admin's contact info is included
 *  inline — once accepted, the caregiver can see and contact whoever
 *  posted the job. */
export interface JobAssignedRecord extends JobWithMyApplication {
  job_poster: { full_name: string; phone: string } | null;
}

export interface CreateJobInput {
  care_receiver_id: string;
  city: City;
  area?: string | null;
  description?: string | null;
  duty_type: DutyType;
  frequency_of_care: FrequencyOfCare;
  start_time?: string | null;
  end_time?: string | null;
  start_date?: string | null;
  languages: Language[];
  salary_amount: number;
  preferred_gender?: string | null;
  preferred_religion?: string | null;
  posted_by: string;
}

export interface UpdateJobInput {
  city: City;
  area?: string | null;
  description?: string | null;
  duty_type: DutyType;
  frequency_of_care: FrequencyOfCare;
  start_time?: string | null;
  end_time?: string | null;
  start_date?: string | null;
  languages: Language[];
  salary_amount: number;
  preferred_gender?: string | null;
  preferred_religion?: string | null;
  /** Only set when the edit should also repost a closed job — omitted
   *  leaves status untouched. When set, `posted_at` is also bumped to
   *  NOW(), restarting the 3-day apply-by urgency window. */
  status?: JobStatus;
}

export interface ListJobsFilters {
  status?: JobStatus;
  city?: City;
}

export interface ListPage {
  page: number;
  limit: number;
}

function buildJobsWhereClause(filters: ListJobsFilters): { clause: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];
  if (filters.status) {
    params.push(filters.status);
    conditions.push(`status = $${params.length}`);
  }
  if (filters.city) {
    params.push(filters.city);
    conditions.push(`city = $${params.length}`);
  }
  return { clause: conditions.length ? `WHERE ${conditions.join(' AND ')}` : '', params };
}

@Injectable()
export class JobsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(input: CreateJobInput, client?: PoolClient): Promise<JobRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<JobRecord>(
      `INSERT INTO jobs
         (care_receiver_id, city, area, description, duty_type, frequency_of_care, start_time, end_time,
          start_date, languages, salary_amount, preferred_gender, preferred_religion, posted_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       RETURNING *`,
      [
        input.care_receiver_id,
        input.city,
        input.area ?? null,
        input.description ?? null,
        input.duty_type,
        input.frequency_of_care,
        input.start_time ?? null,
        input.end_time ?? null,
        input.start_date ?? null,
        JSON.stringify(input.languages),
        input.salary_amount,
        input.preferred_gender ?? null,
        input.preferred_religion ?? null,
        input.posted_by,
      ],
    );
    return result.rows[0];
  }

  async findById(id: string): Promise<JobRecord | null> {
    const result = await this.db.query<JobRecord>('SELECT * FROM jobs WHERE id = $1', [id]);
    return result.rows[0] ?? null;
  }

  async listForAdmin(
    filters: ListJobsFilters,
    page: ListPage,
  ): Promise<{ items: JobRecord[]; total: number }> {
    const { clause, params } = buildJobsWhereClause(filters);
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<JobRecord>(
        `SELECT * FROM jobs ${clause}
         ORDER BY created_at DESC
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM jobs ${clause}`, params),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Active jobs only, with the caregiver's own application status (if any)
   *  and the full care_receiver joined in — lets the caregiver-app show
   *  "already applied" state and the About Patient / About Patient
   *  Condition details directly on the jobs list, without a second
   *  round trip per job. */
  async listActiveForCaregiver(
    profileId: string,
    page: ListPage,
  ): Promise<{ items: JobWithMyApplication[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<JobWithMyApplication>(
        `SELECT j.*, to_jsonb(cr) AS care_receiver,
           CASE WHEN ja.id IS NULL THEN NULL ELSE jsonb_build_object(
             'status', ja.status,
             'applied_at', ja.applied_at,
             'accepted_at', ja.accepted_at,
             'rejected_at', ja.rejected_at,
             'completed_at', ja.completed_at,
             'decided_by_admin', ja.decided_by IS NOT NULL
           ) END AS my_application
         FROM jobs j
         JOIN care_receivers cr ON cr.id = j.care_receiver_id
         LEFT JOIN job_applications ja ON ja.job_id = j.id AND ja.profile_id = $1
         WHERE j.status = 'active'
         ORDER BY j.created_at DESC
         LIMIT $2 OFFSET $3`,
        [profileId, page.limit, offset],
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM jobs WHERE status = 'active'`),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Every job this caregiver is currently accepted onto or has completed —
   *  a caregiver can hold more than one at once, so unlike
   *  listActiveForCaregiver this isn't filtered to active jobs (an accepted
   *  job closes immediately) and isn't limited to one row. Durable history:
   *  completed jobs stay in the list rather than disappearing. */
  async listAssignedForCaregiver(profileId: string): Promise<JobAssignedRecord[]> {
    const result = await this.db.query<JobAssignedRecord>(
      `SELECT j.*, to_jsonb(cr) AS care_receiver,
         jsonb_build_object(
           'status', ja.status,
           'applied_at', ja.applied_at,
           'accepted_at', ja.accepted_at,
           'rejected_at', ja.rejected_at,
           'completed_at', ja.completed_at,
           'decided_by_admin', ja.decided_by IS NOT NULL
         ) AS my_application,
         jsonb_build_object('full_name', u.full_name, 'phone', u.phone) AS job_poster
       FROM job_applications ja
       JOIN jobs j ON j.id = ja.job_id
       JOIN care_receivers cr ON cr.id = j.care_receiver_id
       JOIN users u ON u.id = j.posted_by
       WHERE ja.profile_id = $1 AND ja.status IN ('accepted', 'completed')
       ORDER BY ja.updated_at DESC`,
      [profileId],
    );
    return result.rows;
  }

  async update(id: string, input: UpdateJobInput, client?: PoolClient): Promise<JobRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<JobRecord>(
      `UPDATE jobs SET
         city = $1, area = $2, description = $3, duty_type = $4, frequency_of_care = $5,
         start_time = $6, end_time = $7, start_date = $8, languages = $9, salary_amount = $10,
         preferred_gender = $11, preferred_religion = $12, status = COALESCE($13, status),
         posted_at = CASE WHEN $13::text IS NOT NULL THEN NOW() ELSE posted_at END,
         updated_at = NOW()
       WHERE id = $14
       RETURNING *`,
      [
        input.city,
        input.area ?? null,
        input.description ?? null,
        input.duty_type,
        input.frequency_of_care,
        input.start_time ?? null,
        input.end_time ?? null,
        input.start_date ?? null,
        JSON.stringify(input.languages),
        input.salary_amount,
        input.preferred_gender ?? null,
        input.preferred_religion ?? null,
        input.status ?? null,
        id,
      ],
    );
    return result.rows[0];
  }

  async close(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(`UPDATE jobs SET status = 'closed', updated_at = NOW() WHERE id = $1`, [id]);
  }

  async reopen(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(`UPDATE jobs SET status = 'active', updated_at = NOW() WHERE id = $1`, [id]);
  }
}
