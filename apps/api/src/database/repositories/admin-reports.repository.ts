import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface UnassignedOrNoDutyRow {
  profile_id: string;
  user_id: string;
  caregiver_number: number;
  full_name: string;
  phone: string;
  verification_status: string;
  ever_had_duty: boolean;
}

export interface StalledDutyRow {
  profile_id: string;
  caregiver_number: number;
  full_name: string;
  phone: string;
  engagement_type: 'job' | 'requirement';
  job_number: number | null;
  admin_job_number: number | null;
  patient_job_number: number | null;
  requirement_number: number | null;
  accepted_at: Date;
  days_since_accepted: number;
}

export interface OverThresholdActiveRow {
  profile_id: string;
  caregiver_number: number;
  full_name: string;
  phone: string;
  accepted_count: number;
}

export interface CaregiverActivityRow {
  profile_id: string;
  caregiver_number: number;
  full_name: string;
  phone: string;
  activity_count: number;
}

export interface PatientJobRow {
  profile_id: string;
  user_id: string;
  patient_number: number;
  full_name: string;
  phone: string;
  job_id: string;
  job_number: number;
  admin_job_number: number | null;
  patient_job_number: number | null;
  job_status: string;
}

export interface PatientNoApplicantsRow extends PatientJobRow {
  posted_at: Date;
}

export type PatientNoPendingCandidateRow = PatientJobRow;

export interface PatientUnconvertedApplicantsRow extends PatientJobRow {
  applicant_count: number;
}

export interface PatientActivityRow {
  profile_id: string;
  user_id: string;
  patient_number: number;
  full_name: string;
  phone: string;
  activity_count: number;
}

export interface OrganisationRow {
  profile_id: string;
  user_id: string;
  org_number: number;
  organisation_name: string;
  full_name: string;
  phone: string;
}

export type OrganisationNoJobsPostedRow = OrganisationRow;

export interface OrganisationNoApplicantsRow extends OrganisationRow {
  live_requirement_count: number;
}

export interface OrganisationUnconvertedApplicantsRow extends OrganisationRow {
  applicant_count: number;
}

export interface OrganisationActivityRow extends OrganisationRow {
  activity_count: number;
}

/** Cross-cutting operational reports for admin-web's Reports screen — see
 *  CLAUDE.md's Admin Reports section for the exact semantics of each query.
 *  Unlike the other admin-*.repository.ts files (each scoped to one entity's
 *  own profile+users join), these deliberately span multiple tables
 *  (job_applications, organisation_requirement_applications, jobs,
 *  organisation_requirements) per query, so they live in their own
 *  repository rather than bloating an existing one. */
@Injectable()
export class AdminReportsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Caregivers not currently `assigned` — includes an `ever_had_duty` flag
   *  so admin can tell "between jobs" apart from "never placed". A caregiver
   *  can never be duty-free while `assigned`, so this single WHERE clause
   *  covers "unassigned OR no duty" in full. */
  async findUnassignedOrNoDutyCaregivers(): Promise<UnassignedOrNoDutyRow[]> {
    const result = await this.db.query<UnassignedOrNoDutyRow>(
      `SELECT
         cp.id AS profile_id, cp.user_id, cp.caregiver_number, u.full_name, u.phone,
         cp.verification_status,
         EXISTS (
           SELECT 1 FROM job_applications ja WHERE ja.profile_id = cp.id AND ja.status IN ('accepted', 'completed')
           UNION ALL
           SELECT 1 FROM organisation_requirement_applications ora
             WHERE ora.profile_id = cp.id AND ora.status IN ('accepted', 'completed')
         ) AS ever_had_duty
       FROM caregiver_profiles cp
       JOIN users u ON u.id = cp.user_id
       WHERE cp.verification_status != 'assigned'
       ORDER BY u.full_name`,
    );
    return result.rows;
  }

  /** One row per currently-`accepted` engagement (job or organisation
   *  requirement — both count toward `assigned`) whose `accepted_at` is
   *  older than `days`. */
  async findStalledDuty(days: number): Promise<StalledDutyRow[]> {
    const result = await this.db.query<StalledDutyRow>(
      `SELECT
         cp.id AS profile_id, cp.caregiver_number, u.full_name, u.phone,
         'job' AS engagement_type,
         j.job_number, j.admin_job_number, j.patient_job_number, NULL::int AS requirement_number,
         ja.accepted_at,
         EXTRACT(DAY FROM NOW() - ja.accepted_at)::int AS days_since_accepted
       FROM job_applications ja
       JOIN caregiver_profiles cp ON cp.id = ja.profile_id
       JOIN users u ON u.id = cp.user_id
       JOIN jobs j ON j.id = ja.job_id
       WHERE ja.status = 'accepted' AND ja.accepted_at <= NOW() - ($1::int * INTERVAL '1 day')
       UNION ALL
       SELECT
         cp.id AS profile_id, cp.caregiver_number, u.full_name, u.phone,
         'requirement' AS engagement_type,
         NULL::int, NULL::int, NULL::int, r.requirement_number,
         ora.accepted_at,
         EXTRACT(DAY FROM NOW() - ora.accepted_at)::int AS days_since_accepted
       FROM organisation_requirement_applications ora
       JOIN caregiver_profiles cp ON cp.id = ora.profile_id
       JOIN users u ON u.id = cp.user_id
       JOIN organisation_requirements r ON r.id = ora.requirement_id
       WHERE ora.status = 'accepted' AND ora.accepted_at <= NOW() - ($1::int * INTERVAL '1 day')
       ORDER BY accepted_at ASC`,
      [days],
    );
    return result.rows;
  }

  /** Caregivers whose count of currently-`accepted` engagements (jobs +
   *  organisation requirements combined) exceeds `minJobs`. */
  async findOverThresholdActiveCaregivers(minJobs: number): Promise<OverThresholdActiveRow[]> {
    const result = await this.db.query<OverThresholdActiveRow>(
      `WITH accepted_counts AS (
         SELECT profile_id, COUNT(*)::int AS accepted_count FROM (
           SELECT profile_id FROM job_applications WHERE status = 'accepted'
           UNION ALL
           SELECT profile_id FROM organisation_requirement_applications WHERE status = 'accepted'
         ) combined
         GROUP BY profile_id
       )
       SELECT cp.id AS profile_id, cp.caregiver_number, u.full_name, u.phone, ac.accepted_count
       FROM accepted_counts ac
       JOIN caregiver_profiles cp ON cp.id = ac.profile_id
       JOIN users u ON u.id = cp.user_id
       WHERE ac.accepted_count > $1
       ORDER BY ac.accepted_count DESC`,
      [minJobs],
    );
    return result.rows;
  }

  /** Every caregiver ranked by count of applications (jobs + organisation
   *  requirements combined) submitted in the last `days` days — sortable
   *  asc/desc so this one query answers both "most active" and "least
   *  active". Caregivers with zero activity in the window are included
   *  (count 0), which is exactly what "least active" needs to surface. */
  async findCaregiverActivity(days: number, order: 'asc' | 'desc'): Promise<CaregiverActivityRow[]> {
    const orderDirection = order === 'asc' ? 'ASC' : 'DESC';
    const result = await this.db.query<CaregiverActivityRow>(
      `WITH combined_applications AS (
         SELECT profile_id, applied_at FROM job_applications
         UNION ALL
         SELECT profile_id, applied_at FROM organisation_requirement_applications
       )
       SELECT
         cp.id AS profile_id, cp.caregiver_number, u.full_name, u.phone,
         COUNT(c.applied_at) FILTER (WHERE c.applied_at >= NOW() - ($1::int * INTERVAL '1 day'))::int AS activity_count
       FROM caregiver_profiles cp
       JOIN users u ON u.id = cp.user_id
       LEFT JOIN combined_applications c ON c.profile_id = cp.id
       GROUP BY cp.id, cp.caregiver_number, u.full_name, u.phone
       ORDER BY activity_count ${orderDirection}, u.full_name ASC`,
      [days],
    );
    return result.rows;
  }

  /** Individuals whose current live job (active or pending_review — same
   *  "live" definition as JOB_009's one-live-requirement rule) has received
   *  zero applications in the last `days` days. */
  async findPatientsWithNoApplicants(days: number): Promise<PatientNoApplicantsRow[]> {
    const result = await this.db.query<PatientNoApplicantsRow>(
      `SELECT
         ip.id AS profile_id, ip.user_id, ip.patient_number, u.full_name, u.phone,
         j.id AS job_id, j.job_number, j.admin_job_number, j.patient_job_number, j.status AS job_status,
         j.posted_at
       FROM individual_profiles ip
       JOIN users u ON u.id = ip.user_id
       JOIN jobs j ON j.posted_by = ip.user_id AND j.status IN ('active', 'pending_review')
       WHERE NOT EXISTS (
         SELECT 1 FROM job_applications ja
         WHERE ja.job_id = j.id AND ja.applied_at >= NOW() - ($1::int * INTERVAL '1 day')
       )
       ORDER BY j.posted_at ASC`,
      [days],
    );
    return result.rows;
  }

  /** Individuals whose current live job has zero applications still
   *  `applied` (awaiting a decision) right now — nothing on their plate to
   *  act on, whether because nobody's applied yet or every applicant has
   *  already been decided. */
  async findPatientsWithNoPendingCandidate(): Promise<PatientNoPendingCandidateRow[]> {
    const result = await this.db.query<PatientNoPendingCandidateRow>(
      `SELECT
         ip.id AS profile_id, ip.user_id, ip.patient_number, u.full_name, u.phone,
         j.id AS job_id, j.job_number, j.admin_job_number, j.patient_job_number, j.status AS job_status
       FROM individual_profiles ip
       JOIN users u ON u.id = ip.user_id
       JOIN jobs j ON j.posted_by = ip.user_id AND j.status IN ('active', 'pending_review')
       WHERE NOT EXISTS (
         SELECT 1 FROM job_applications ja WHERE ja.job_id = j.id AND ja.status = 'applied'
       )
       ORDER BY j.posted_at ASC`,
    );
    return result.rows;
  }

  /** Individuals whose current live job has at least one applicant ever but
   *  zero currently `accepted` — candidates came, none were converted. */
  async findPatientsWithUnconvertedApplicants(): Promise<PatientUnconvertedApplicantsRow[]> {
    const result = await this.db.query<PatientUnconvertedApplicantsRow>(
      `SELECT
         ip.id AS profile_id, ip.user_id, ip.patient_number, u.full_name, u.phone,
         j.id AS job_id, j.job_number, j.admin_job_number, j.patient_job_number, j.status AS job_status,
         COUNT(ja.id)::int AS applicant_count
       FROM individual_profiles ip
       JOIN users u ON u.id = ip.user_id
       JOIN jobs j ON j.posted_by = ip.user_id AND j.status IN ('active', 'pending_review')
       JOIN job_applications ja ON ja.job_id = j.id
       GROUP BY ip.id, ip.user_id, ip.patient_number, u.full_name, u.phone, j.id, j.job_number, j.admin_job_number,
         j.patient_job_number, j.status, j.posted_at
       HAVING COUNT(ja.id) FILTER (WHERE ja.status = 'accepted') = 0
       ORDER BY j.posted_at DESC`,
    );
    return result.rows;
  }

  /** Every individual ranked by count of jobs posted (own submission, i.e.
   *  `created_at` — not `posted_at`, which reflects admin approval timing
   *  they don't control) in the last `days` days — sortable asc/desc. */
  async findPatientActivity(days: number, order: 'asc' | 'desc'): Promise<PatientActivityRow[]> {
    const orderDirection = order === 'asc' ? 'ASC' : 'DESC';
    const result = await this.db.query<PatientActivityRow>(
      `SELECT
         ip.id AS profile_id, ip.user_id, ip.patient_number, u.full_name, u.phone,
         COUNT(j.id) FILTER (WHERE j.created_at >= NOW() - ($1::int * INTERVAL '1 day'))::int AS activity_count
       FROM individual_profiles ip
       JOIN users u ON u.id = ip.user_id
       LEFT JOIN jobs j ON j.posted_by = ip.user_id
       GROUP BY ip.id, ip.user_id, ip.patient_number, u.full_name, u.phone
       ORDER BY activity_count ${orderDirection}, u.full_name ASC`,
      [days],
    );
    return result.rows;
  }

  /** Organisations with zero organisation_requirements rows, ever
   *  (all-time, no day threshold — matches the literal "do not have any
   *  jobs posted" ask). */
  async findOrganisationsWithNoJobsPosted(): Promise<OrganisationNoJobsPostedRow[]> {
    const result = await this.db.query<OrganisationNoJobsPostedRow>(
      `SELECT op.id AS profile_id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone
       FROM organisation_profiles op
       JOIN users u ON u.id = op.user_id
       WHERE NOT EXISTS (SELECT 1 FROM organisation_requirements r WHERE r.posted_by = op.user_id)
       ORDER BY op.organisation_name`,
    );
    return result.rows;
  }

  /** Organisations with at least one live requirement (active or
   *  pending_review), where NONE of their live requirements received an
   *  application in the last `days` days — an org can have many
   *  simultaneous requirements (unlike Individual's one-live-limit), so
   *  this is evaluated across all of them at once, one row per org. */
  async findOrganisationsWithNoApplicants(days: number): Promise<OrganisationNoApplicantsRow[]> {
    const result = await this.db.query<OrganisationNoApplicantsRow>(
      `SELECT
         op.id AS profile_id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone,
         COUNT(r.id)::int AS live_requirement_count
       FROM organisation_profiles op
       JOIN users u ON u.id = op.user_id
       JOIN organisation_requirements r ON r.posted_by = op.user_id AND r.status IN ('active', 'pending_review')
       WHERE NOT EXISTS (
         SELECT 1 FROM organisation_requirement_applications ora
         JOIN organisation_requirements r2 ON r2.id = ora.requirement_id
         WHERE r2.posted_by = op.user_id AND r2.status IN ('active', 'pending_review')
           AND ora.applied_at >= NOW() - ($1::int * INTERVAL '1 day')
       )
       GROUP BY op.id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone
       ORDER BY op.organisation_name`,
      [days],
    );
    return result.rows;
  }

  /** Organisations whose live requirements have at least one applicant ever
   *  but zero currently `accepted` across all of them — candidates came,
   *  none were converted, on any of their open postings. */
  async findOrganisationsWithUnconvertedApplicants(): Promise<OrganisationUnconvertedApplicantsRow[]> {
    const result = await this.db.query<OrganisationUnconvertedApplicantsRow>(
      `SELECT
         op.id AS profile_id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone,
         COUNT(ora.id)::int AS applicant_count
       FROM organisation_profiles op
       JOIN users u ON u.id = op.user_id
       JOIN organisation_requirements r ON r.posted_by = op.user_id AND r.status IN ('active', 'pending_review')
       JOIN organisation_requirement_applications ora ON ora.requirement_id = r.id
       GROUP BY op.id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone
       HAVING COUNT(ora.id) FILTER (WHERE ora.status = 'accepted') = 0
       ORDER BY op.organisation_name`,
    );
    return result.rows;
  }

  /** Every organisation ranked by count of requirements posted (own
   *  submission, `created_at`) in the last `days` days — sortable
   *  asc/desc. */
  async findOrganisationActivity(days: number, order: 'asc' | 'desc'): Promise<OrganisationActivityRow[]> {
    const orderDirection = order === 'asc' ? 'ASC' : 'DESC';
    const result = await this.db.query<OrganisationActivityRow>(
      `SELECT
         op.id AS profile_id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone,
         COUNT(r.id) FILTER (WHERE r.created_at >= NOW() - ($1::int * INTERVAL '1 day'))::int AS activity_count
       FROM organisation_profiles op
       JOIN users u ON u.id = op.user_id
       LEFT JOIN organisation_requirements r ON r.posted_by = op.user_id
       GROUP BY op.id, op.user_id, op.org_number, op.organisation_name, u.full_name, u.phone
       ORDER BY activity_count ${orderDirection}, u.full_name ASC`,
      [days],
    );
    return result.rows;
  }
}
