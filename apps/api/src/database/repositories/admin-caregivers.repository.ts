import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { Gender, Qualification, Religion, VerificationStatus } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

export interface DashboardStats {
  total_caregivers: number;
  pending_call: number;
  available: number;
  unavailable: number;
  assigned: number;
  rejected: number;
  pending_edits_count: number;
  new_registrations_24h: number;
  new_registrations_7d: number;
  /** jobs.status = 'pending_review' + organisation_requirements.status =
   *  'pending_review' combined — every NurseNow posting currently awaiting
   *  admin's legitimacy review, across both posting types. Populated by
   *  AdminService.getDashboardStats, not this repository's own query. */
  jobs_pending_approval: number;
  /** users.role = 'organisation' created in the last 7 days. Populated by
   *  AdminService.getDashboardStats, not this repository's own query. */
  new_organisations_7d: number;
  /** users.role = 'individual' created in the last 7 days. Populated by
   *  AdminService.getDashboardStats, not this repository's own query. */
  new_individuals_7d: number;
  /** support_tickets.status = 'open' — feeds the Tickets sidebar badge.
   *  Populated by AdminService.getDashboardStats, not this repository's
   *  own query. */
  open_tickets_count: number;
}

export interface AdminCaregiverListItem {
  user_id: string;
  profile_id: string;
  caregiver_number: number;
  full_name: string;
  phone: string;
  gender: Gender;
  age: number;
  highest_qualification: Qualification | null;
  verification_status: VerificationStatus;
  created_at: Date;
}

export interface AdminCaregiverListFilters {
  search?: string;
  status?: VerificationStatus;
  qualification?: Qualification;
  gender?: Gender;
  languages?: string[];
  preferredCity?: string;
  fromDate?: string;
  toDate?: string;
}

export interface AdminCaregiverListSort {
  sort: 'created_at' | 'full_name' | 'age';
  order: 'asc' | 'desc';
  page: number;
  limit: number;
}

export interface AdminCaregiverDetail {
  id: string;
  user_id: string;
  caregiver_number: number;
  full_name: string;
  phone: string;
  email: string | null;
  gender: Gender;
  age: number;
  selfie_photo_url: string | null;
  highest_qualification: Qualification | null;
  qualification_document_url: string | null;
  aadhaar_document_url: string | null;
  other_document_urls: string[];
  religion: Religion | null;
  terms_accepted: boolean;
  verification_status: VerificationStatus;
  rejection_message: string | null;
  has_pending_edits: boolean;
  created_at: Date;
  verified_at: Date | null;
}

const SORT_COLUMNS: Record<AdminCaregiverListSort['sort'], string> = {
  created_at: 'cp.created_at',
  full_name: 'u.full_name',
  age: 'cp.age',
};

function buildWhereClause(filters: AdminCaregiverListFilters): { clause: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.search) {
    params.push(`%${filters.search}%`);
    conditions.push(
      `(u.full_name ILIKE $${params.length} OR u.phone ILIKE $${params.length} OR ('NUR-' || cp.caregiver_number::text) ILIKE $${params.length})`,
    );
  }
  if (filters.status) {
    params.push(filters.status);
    conditions.push(`cp.verification_status = $${params.length}`);
  }
  if (filters.qualification) {
    params.push(filters.qualification);
    conditions.push(`cp.highest_qualification = $${params.length}`);
  }
  if (filters.gender) {
    params.push(filters.gender);
    conditions.push(`cp.gender = $${params.length}`);
  }
  if (filters.languages && filters.languages.length > 0) {
    params.push(filters.languages);
    conditions.push(
      `EXISTS (SELECT 1 FROM caregiver_languages cl WHERE cl.profile_id = cp.id AND cl.language = ANY($${params.length}))`,
    );
  }
  if (filters.preferredCity) {
    params.push(filters.preferredCity);
    conditions.push(
      `EXISTS (SELECT 1 FROM caregiver_preferred_cities cpc WHERE cpc.profile_id = cp.id AND cpc.city = $${params.length})`,
    );
  }
  if (filters.fromDate) {
    params.push(filters.fromDate);
    conditions.push(`cp.created_at >= $${params.length}`);
  }
  if (filters.toDate) {
    params.push(filters.toDate);
    conditions.push(`cp.created_at <= $${params.length}::date + INTERVAL '1 day'`);
  }

  return {
    clause: conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '',
    params,
  };
}

/** One accepted/completed engagement of a caregiver — a job (patient/admin
 *  posted) or an organisation requirement — for the admin caregiver detail. */
export interface CaregiverEngagement {
  kind: 'job' | 'organisation_requirement';
  application_id: string;
  status: 'accepted' | 'completed';
  admin_job_number: number | null;
  patient_job_number: number | null;
  requirement_number: number | null;
  /** Who posted it: a patient's/admin's name, or the organisation's name. */
  poster_name: string | null;
  poster_phone: string | null;
  poster_role: string | null;
  poster_number: number | null;
  patient_name: string | null;
  city: string | null;
  area: string | null;
  duty_type: string | null;
  /** DATE as YYYY-MM-DD; null for organisation requirements (no start date). */
  start_date: string | null;
  accepted_at: Date | null;
  completed_at: Date | null;
  accepted_by_name: string | null;
}

@Injectable()
export class AdminCaregiversRepository {
  constructor(private readonly db: DatabaseService) {}

  async getDashboardStats(): Promise<DashboardStats> {
    const result = await this.db.query<Record<keyof DashboardStats, string>>(
      `SELECT
         COUNT(*) AS total_caregivers,
         COUNT(*) FILTER (WHERE verification_status = 'pending_call') AS pending_call,
         COUNT(*) FILTER (WHERE verification_status = 'available') AS available,
         COUNT(*) FILTER (WHERE verification_status = 'unavailable') AS unavailable,
         COUNT(*) FILTER (WHERE verification_status = 'assigned') AS assigned,
         COUNT(*) FILTER (WHERE verification_status = 'rejected') AS rejected,
         COUNT(*) FILTER (WHERE has_pending_edits = true) AS pending_edits_count,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS new_registrations_24h,
         COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days') AS new_registrations_7d
       FROM caregiver_profiles`,
    );
    const row = result.rows[0];
    return Object.fromEntries(
      Object.entries(row).map(([key, value]) => [key, Number(value)]),
    ) as unknown as DashboardStats;
  }

  async listCaregivers(
    filters: AdminCaregiverListFilters,
    sort: AdminCaregiverListSort,
  ): Promise<{ items: AdminCaregiverListItem[]; total: number }> {
    const { clause, params } = buildWhereClause(filters);
    const sortColumn = SORT_COLUMNS[sort.sort];
    const orderDirection = sort.order === 'asc' ? 'ASC' : 'DESC';
    const offset = (sort.page - 1) * sort.limit;

    const listParams = [...params, sort.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<AdminCaregiverListItem>(
        `SELECT cp.id AS profile_id, cp.user_id, cp.caregiver_number, u.full_name, u.phone, cp.gender, cp.age,
                cp.highest_qualification, cp.verification_status, cp.created_at
         FROM caregiver_profiles cp
         JOIN users u ON u.id = cp.user_id
         ${clause}
         ORDER BY ${sortColumn} ${orderDirection}
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM caregiver_profiles cp JOIN users u ON u.id = cp.user_id ${clause}`,
        params,
      ),
    ]);

    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async getDetailById(profileId: string): Promise<AdminCaregiverDetail | null> {
    const result = await this.db.query<AdminCaregiverDetail>(
      `SELECT cp.id, cp.user_id, cp.caregiver_number, u.full_name, u.phone, u.email, cp.gender, cp.age,
              cp.selfie_photo_url, cp.highest_qualification, cp.qualification_document_url,
              cp.aadhaar_document_url, cp.other_document_urls, cp.religion,
              cp.terms_accepted,
              cp.verification_status, cp.rejection_message,
              cp.has_pending_edits, cp.created_at, cp.verified_at
       FROM caregiver_profiles cp
       JOIN users u ON u.id = cp.user_id
       WHERE cp.id = $1`,
      [profileId],
    );
    return result.rows[0] ?? null;
  }

  /** Every job and organisation requirement this caregiver is (or was)
   *  accepted onto, active ones first, then by start date. */
  async listEngagements(profileId: string): Promise<CaregiverEngagement[]> {
    const jobs = await this.db.query<CaregiverEngagement>(
      `SELECT 'job' AS kind, ja.id AS application_id, ja.status,
              j.admin_job_number, j.patient_job_number, NULL::int AS requirement_number,
              pu.full_name AS poster_name, pu.phone AS poster_phone, pu.role AS poster_role,
              ip.patient_number AS poster_number, cr.patient_name,
              j.city, j.area, j.duty_type, j.start_date,
              ja.accepted_at, ja.completed_at, du.full_name AS accepted_by_name
       FROM job_applications ja
       JOIN jobs j ON j.id = ja.job_id
       LEFT JOIN users pu ON pu.id = j.posted_by
       LEFT JOIN individual_profiles ip ON ip.user_id = j.posted_by
       LEFT JOIN care_receivers cr ON cr.id = j.care_receiver_id
       LEFT JOIN users du ON du.id = ja.decided_by
       WHERE ja.profile_id = $1 AND ja.status IN ('accepted', 'completed')`,
      [profileId],
    );
    const requirements = await this.db.query<CaregiverEngagement>(
      `SELECT 'organisation_requirement' AS kind, oa.id AS application_id, oa.status,
              NULL::int AS admin_job_number, NULL::int AS patient_job_number,
              r.requirement_number,
              op.organisation_name AS poster_name, pu.phone AS poster_phone, pu.role AS poster_role,
              op.org_number AS poster_number, NULL AS patient_name,
              op.city, op.area, NULL AS duty_type, NULL::date AS start_date,
              oa.accepted_at, oa.completed_at, du.full_name AS accepted_by_name
       FROM organisation_requirement_applications oa
       JOIN organisation_requirements r ON r.id = oa.requirement_id
       LEFT JOIN users pu ON pu.id = r.posted_by
       LEFT JOIN organisation_profiles op ON op.user_id = r.posted_by
       LEFT JOIN users du ON du.id = oa.decided_by
       WHERE oa.profile_id = $1 AND oa.status IN ('accepted', 'completed')`,
      [profileId],
    );
    const rank = (e: CaregiverEngagement) => (e.status === 'accepted' ? 0 : 1);
    return [...jobs.rows, ...requirements.rows].sort(
      (a, b) =>
        rank(a) - rank(b) ||
        String(a.start_date ?? '9999').localeCompare(String(b.start_date ?? '9999')) ||
        new Date(b.accepted_at ?? 0).getTime() - new Date(a.accepted_at ?? 0).getTime(),
    );
  }

  /** Admin override — any VerificationStatus, from any current status (no
   *  transition-matrix check; that lives, if anywhere, in the service
   *  layer, and today there isn't one — this is deliberately permissive).
   *  `rejection_message` is cleared for every target except `rejected`,
   *  so it's never stale once a caregiver is admin-moved off `rejected`.
   *  `verified_at`/`verified_by` are (re-)stamped only when moving to
   *  `available` — every other status leaves them untouched. */
  async updateStatus(
    profileId: string,
    status: VerificationStatus,
    rejectionMessage: string | null,
    adminId: string,
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    if (status === 'available') {
      await runner.query(
        `UPDATE caregiver_profiles
         SET verification_status = $2, verified_at = NOW(), verified_by = $3, rejection_message = NULL,
             updated_at = NOW()
         WHERE id = $1`,
        [profileId, status, adminId],
      );
    } else if (status === 'rejected') {
      await runner.query(
        `UPDATE caregiver_profiles
         SET verification_status = $2, rejection_message = $3, updated_at = NOW()
         WHERE id = $1`,
        [profileId, status, rejectionMessage],
      );
    } else {
      await runner.query(
        `UPDATE caregiver_profiles
         SET verification_status = $2, rejection_message = NULL, updated_at = NOW()
         WHERE id = $1`,
        [profileId, status],
      );
    }
  }
}
