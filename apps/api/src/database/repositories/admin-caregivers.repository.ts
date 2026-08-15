import { Injectable } from '@nestjs/common';
import { Gender, Qualification, Religion, ServiceMode, VerificationStatus, WorkType } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

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
}

export interface AdminCaregiverListItem {
  user_id: string;
  profile_id: string;
  full_name: string;
  phone: string;
  gender: Gender;
  age: number;
  highest_qualification: Qualification | null;
  service_modes: ServiceMode[];
  work_types: WorkType[];
  verification_status: VerificationStatus;
  created_at: Date;
}

export interface AdminCaregiverListFilters {
  search?: string;
  status?: VerificationStatus;
  qualification?: Qualification;
  languages?: string[];
  serviceMode?: ServiceMode;
  workType?: WorkType;
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
  salary: string | null;
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
    conditions.push(`(u.full_name ILIKE $${params.length} OR u.phone ILIKE $${params.length})`);
  }
  if (filters.status) {
    params.push(filters.status);
    conditions.push(`cp.verification_status = $${params.length}`);
  }
  if (filters.qualification) {
    params.push(filters.qualification);
    conditions.push(`cp.highest_qualification = $${params.length}`);
  }
  if (filters.languages && filters.languages.length > 0) {
    params.push(filters.languages);
    conditions.push(
      `EXISTS (SELECT 1 FROM caregiver_languages cl WHERE cl.profile_id = cp.id AND cl.language = ANY($${params.length}))`,
    );
  }
  if (filters.serviceMode) {
    params.push(filters.serviceMode);
    conditions.push(
      `EXISTS (SELECT 1 FROM caregiver_service_modes csm WHERE csm.profile_id = cp.id AND csm.service_mode = $${params.length})`,
    );
  }
  if (filters.workType) {
    params.push(filters.workType);
    conditions.push(
      `EXISTS (SELECT 1 FROM caregiver_work_types cwt WHERE cwt.profile_id = cp.id AND cwt.work_type = $${params.length})`,
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
        `SELECT cp.id AS profile_id, cp.user_id, u.full_name, u.phone, cp.gender, cp.age,
                cp.highest_qualification, cp.verification_status, cp.created_at,
                COALESCE(sm.service_modes, ARRAY[]::text[]) AS service_modes,
                COALESCE(wt.work_types, ARRAY[]::text[]) AS work_types
         FROM caregiver_profiles cp
         JOIN users u ON u.id = cp.user_id
         LEFT JOIN (
           SELECT profile_id, array_agg(service_mode) AS service_modes
           FROM caregiver_service_modes GROUP BY profile_id
         ) sm ON sm.profile_id = cp.id
         LEFT JOIN (
           SELECT profile_id, array_agg(work_type) AS work_types
           FROM caregiver_work_types GROUP BY profile_id
         ) wt ON wt.profile_id = cp.id
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
      `SELECT cp.id, cp.user_id, u.full_name, u.phone, u.email, cp.gender, cp.age,
              cp.selfie_photo_url, cp.highest_qualification, cp.qualification_document_url,
              cp.aadhaar_document_url, cp.other_document_urls, cp.religion, cp.salary,
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
  ): Promise<void> {
    if (status === 'available') {
      await this.db.query(
        `UPDATE caregiver_profiles
         SET verification_status = $2, verified_at = NOW(), verified_by = $3, rejection_message = NULL,
             updated_at = NOW()
         WHERE id = $1`,
        [profileId, status, adminId],
      );
    } else if (status === 'rejected') {
      await this.db.query(
        `UPDATE caregiver_profiles
         SET verification_status = $2, rejection_message = $3, updated_at = NOW()
         WHERE id = $1`,
        [profileId, status, rejectionMessage],
      );
    } else {
      await this.db.query(
        `UPDATE caregiver_profiles
         SET verification_status = $2, rejection_message = NULL, updated_at = NOW()
         WHERE id = $1`,
        [profileId, status],
      );
    }
  }
}
