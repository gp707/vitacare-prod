import { Injectable } from '@nestjs/common';
import {
  City,
  DutyType,
  FrequencyOfCare,
  Gender,
  JobApplicationStatus,
  JobStatus,
  Language,
} from '@vitacare/shared-constants';
import { PoolClient } from 'pg';
import { DatabaseService, QueryRunner } from '../database.service';
import { CareReceiverRecord } from './care-receivers.repository';

export interface JobRecord {
  id: string;
  /** Internal only — no longer the user-facing display id (see
   *  admin_job_number/patient_job_number below); still used for
   *  audit-log job resolution. */
  job_number: number;
  /** Set only when this job was posted by an admin — the raw integer
   *  backing the "ADMIN-JOB-<n>" display id (migration 047, starts at
   *  500). Exactly one of admin_job_number/patient_job_number is set. */
  admin_job_number: number | null;
  /** Set only when this job was posted by a NurseNow individual — the
   *  raw integer backing the "PAT-JOB-<n>" display id (migration 047,
   *  starts at 500). */
  patient_job_number: number | null;
  care_receiver_id: string;
  city: City;
  area: string | null;
  description: string | null;
  duty_type: DutyType;
  /** Null only for a NurseNow individual-posted job still awaiting admin
   *  approval (status = pending_review) — admin sets it during approval,
   *  same as salary_amount. */
  frequency_of_care: FrequencyOfCare | null;
  start_time: string | null;
  end_time: string | null;
  start_date: string | null;
  languages: Language[];
  salary_amount: number | null;
  preferred_gender: string | null;
  preferred_religion: string | null;
  status: JobStatus;
  posted_by: string;
  /** Only set when an admin rejects a pending_review job — null otherwise,
   *  including for a normal close. */
  rejection_reason: string | null;
  /** Effective "went live" timestamp — starts equal to created_at, bumped
   *  to NOW() only when a closed job is edited-and-reposted. The 3-day
   *  apply-by urgency window is always computed from this, not created_at. */
  posted_at: Date;
  created_at: Date;
  updated_at: Date;
}

/** listForAdmin's shape — adds the poster's role/name (via a users join)
 *  so admin-web can label a NurseNow individual's posting distinctly from
 *  admin's own, without a second round trip. Not present on plain
 *  JobRecord (e.g. findById) since most callers don't need it. */
export interface JobListItemForAdmin extends JobRecord {
  posted_by_role: string;
  posted_by_name: string;
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
  /** Null for a NurseNow individual posting — admin sets it on approval. */
  frequency_of_care: FrequencyOfCare | null;
  start_time?: string | null;
  end_time?: string | null;
  start_date?: string | null;
  languages: Language[];
  /** Null for a NurseNow individual posting — admin sets it on approval. */
  salary_amount: number | null;
  preferred_gender?: string | null;
  preferred_religion?: string | null;
  posted_by: string;
  /** Omitted defaults to 'active' (admin's own postings, unchanged
   *  behavior). A NurseNow individual posting passes 'pending_review'. */
  status?: JobStatus;
  /** Which display-id sequence to advance — 'admin' populates
   *  admin_job_number, 'individual' populates patient_job_number. */
  posted_by_role: 'admin' | 'individual';
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
  posted_by?: string;
  /** Patient's gender, on care_receivers — requires the cr join below. */
  gender?: Gender;
  duty_type?: DutyType;
  /** Matches jobs whose languages array includes this one value. */
  language?: Language;
  /** Jobs posted by any user of this role — e.g. 'individual' to see just
   *  NurseNow patient/family postings vs admin's own. Requires the users
   *  join added in listForAdmin below. */
  posted_by_role?: string;
  /** Matches against the job's display id (ADMIN-JOB-<n>/PAT-JOB-<n>) or the
   *  raw job_number. */
  search?: string;
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
    conditions.push(`j.status = $${params.length}`);
  }
  if (filters.city) {
    params.push(filters.city);
    conditions.push(`j.city = $${params.length}`);
  }
  if (filters.posted_by) {
    params.push(filters.posted_by);
    conditions.push(`j.posted_by = $${params.length}`);
  }
  if (filters.duty_type) {
    params.push(filters.duty_type);
    conditions.push(`j.duty_type = $${params.length}`);
  }
  if (filters.gender) {
    params.push(filters.gender);
    conditions.push(`cr.gender = $${params.length}`);
  }
  if (filters.language) {
    params.push(JSON.stringify([filters.language]));
    conditions.push(`j.languages @> $${params.length}::jsonb`);
  }
  if (filters.posted_by_role) {
    params.push(filters.posted_by_role);
    conditions.push(`u.role = $${params.length}`);
  }
  if (filters.search) {
    params.push(`%${filters.search}%`);
    conditions.push(
      `(('ADMIN-JOB-' || j.admin_job_number::text) ILIKE $${params.length}
        OR ('PAT-JOB-' || j.patient_job_number::text) ILIKE $${params.length}
        OR j.job_number::text ILIKE $${params.length})`,
    );
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
          start_date, languages, salary_amount, preferred_gender, preferred_religion, posted_by, status,
          admin_job_number, patient_job_number)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, COALESCE($15, 'active'),
          CASE WHEN $16 = 'admin' THEN nextval('jobs_admin_job_number_seq') ELSE NULL END,
          CASE WHEN $16 = 'individual' THEN nextval('jobs_patient_job_number_seq') ELSE NULL END)
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
        input.status ?? null,
        input.posted_by_role,
      ],
    );
    return result.rows[0];
  }

  async findById(id: string): Promise<JobRecord | null> {
    const result = await this.db.query<JobRecord>('SELECT * FROM jobs WHERE id = $1', [id]);
    return result.rows[0] ?? null;
  }

  /** A NurseNow individual's own job(s) — in practice zero-or-one given the
   *  one-live-requirement rule, but shaped as a list for symmetry with
   *  listAssignedForCaregiver. */
  async listByPostedBy(postedBy: string): Promise<JobRecord[]> {
    const result = await this.db.query<JobRecord>(
      'SELECT * FROM jobs WHERE posted_by = $1 ORDER BY created_at DESC',
      [postedBy],
    );
    return result.rows;
  }

  /** Used to enforce the one-live-requirement-at-a-time rule for
   *  individual accounts — pending_review counts as live, same as active. */
  async findLiveByPostedBy(postedBy: string): Promise<JobRecord | null> {
    const result = await this.db.query<JobRecord>(
      `SELECT * FROM jobs WHERE posted_by = $1 AND status IN ('pending_review', 'active') LIMIT 1`,
      [postedBy],
    );
    return result.rows[0] ?? null;
  }

  async listForAdmin(
    filters: ListJobsFilters,
    page: ListPage,
  ): Promise<{ items: JobListItemForAdmin[]; total: number }> {
    const { clause, params } = buildJobsWhereClause(filters);
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<JobListItemForAdmin>(
        `SELECT j.*, u.role AS posted_by_role, u.full_name AS posted_by_name
         FROM jobs j
         JOIN care_receivers cr ON cr.id = j.care_receiver_id
         JOIN users u ON u.id = j.posted_by
         ${clause}
         ORDER BY j.created_at DESC
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM jobs j
         JOIN care_receivers cr ON cr.id = j.care_receiver_id
         JOIN users u ON u.id = j.posted_by
         ${clause}`,
        params,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  /** Distinct admins who have posted at least one job — powers the admin-web
   *  "Job Poster" filter dropdown (name + phone, since names can collide). */
  async listPosters(): Promise<{ id: string; full_name: string; phone: string }[]> {
    const result = await this.db.query<{ id: string; full_name: string; phone: string }>(
      `SELECT DISTINCT u.id, u.full_name, u.phone
       FROM users u
       JOIN jobs j ON j.posted_by = u.id
       ORDER BY u.full_name`,
    );
    return result.rows;
  }

  /** Active jobs only, with the caregiver's own application status (if any)
   *  and the full care_receiver joined in — lets the caregiver-app show
   *  "already applied" state and the About Patient / About Patient
   *  Condition details directly on the jobs list, without a second
   *  round trip per job. Filtered to jobs whose preferred_gender is either
   *  unset (no preference) or matches the caregiver's own gender — a
   *  caregiver never sees a job posted for the other gender — plus the
   *  caregiver's own dynamic job-search preferences: preferred_cities and
   *  preferred_duty_types (both via EXISTS/NOT EXISTS against their
   *  junction tables, keyed on profileId — no rows stored for either means
   *  no filter on that dimension) and min_salary_per_day/
   *  min_salary_per_month (each only ever compared against a job of the
   *  matching frequency_of_care — a daily job's salary is never compared
   *  against min_salary_per_month and vice versa). All of this is read
   *  fresh from the caregiver's current profile on every call, so changing
   *  a preference takes effect on the very next list request. */
  async listActiveForCaregiver(
    profileId: string,
    gender: Gender,
    minSalaryPerDay: number | null,
    minSalaryPerMonth: number | null,
    page: ListPage,
  ): Promise<{ items: JobWithMyApplication[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const preferenceFilters = `
         AND (
           NOT EXISTS (SELECT 1 FROM caregiver_preferred_cities cpc WHERE cpc.profile_id = $1)
           OR EXISTS (SELECT 1 FROM caregiver_preferred_cities cpc WHERE cpc.profile_id = $1 AND cpc.city = j.city)
         )
         AND (
           NOT EXISTS (SELECT 1 FROM caregiver_preferred_duty_types cpd WHERE cpd.profile_id = $1)
           OR EXISTS (SELECT 1 FROM caregiver_preferred_duty_types cpd WHERE cpd.profile_id = $1 AND cpd.duty_type = j.duty_type)
         )
         AND (j.frequency_of_care != 'daily' OR $3::int IS NULL OR j.salary_amount >= $3)
         AND (j.frequency_of_care != 'monthly' OR $4::int IS NULL OR j.salary_amount >= $4)`;
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
         WHERE j.status = 'active' AND (j.preferred_gender IS NULL OR j.preferred_gender = $2)
         ${preferenceFilters}
         ORDER BY j.created_at DESC
         LIMIT $5 OFFSET $6`,
        [profileId, gender, minSalaryPerDay, minSalaryPerMonth, page.limit, offset],
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM jobs j
         WHERE j.status = 'active' AND (j.preferred_gender IS NULL OR j.preferred_gender = $2)
         ${preferenceFilters}`,
        [profileId, gender, minSalaryPerDay, minSalaryPerMonth],
      ),
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

  /** Admin declines a pending_review individual-posted job — the
   *  requirement never goes live. Distinct from close(): stores why, so
   *  the individual can see the reason. */
  async reject(id: string, reason: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE jobs SET status = 'closed', rejection_reason = $2, updated_at = NOW() WHERE id = $1`,
      [id, reason],
    );
  }
}
