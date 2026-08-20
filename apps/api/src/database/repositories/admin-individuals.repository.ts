import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export interface AdminIndividualListItem {
  user_id: string;
  patient_number: number;
  full_name: string;
  phone: string;
  is_active: boolean;
  is_job_posting_blocked: boolean;
  block_reason: string | null;
  created_at: Date;
}

export interface AdminIndividualListFilters {
  /** Matches full_name, phone, or the display id (PAT-<n>). */
  search?: string;
  blockStatus?: 'active' | 'job_posting_blocked' | 'blocked';
}

function buildIndividualsWhereClause(filters: AdminIndividualListFilters): {
  clause: string;
  params: unknown[];
} {
  const conditions = [`u.role = 'individual'`];
  const params: unknown[] = [];
  if (filters.search) {
    params.push(`%${filters.search}%`);
    conditions.push(
      `(u.full_name ILIKE $${params.length} OR u.phone ILIKE $${params.length} OR ('PAT-' || ip.patient_number::text) ILIKE $${params.length})`,
    );
  }
  if (filters.blockStatus === 'blocked') {
    conditions.push(`u.is_active = false`);
  } else if (filters.blockStatus === 'job_posting_blocked') {
    conditions.push(`u.is_active = true AND ip.is_job_posting_blocked = true`);
  } else if (filters.blockStatus === 'active') {
    conditions.push(`u.is_active = true AND ip.is_job_posting_blocked = false`);
  }
  return { clause: `WHERE ${conditions.join(' AND ')}`, params };
}

/** Admin-side view of individual (patient/family) accounts — mirrors the
 *  AdminCaregiversRepository / CaregiverProfilesRepository split: self-
 *  service lives in IndividualProfilesRepository, admin listing/block
 *  actions live here. */
@Injectable()
export class AdminIndividualsRepository {
  constructor(private readonly db: DatabaseService) {}

  async listIndividuals(
    filters: AdminIndividualListFilters,
    page: ListPage,
  ): Promise<{ items: AdminIndividualListItem[]; total: number }> {
    const { clause, params } = buildIndividualsWhereClause(filters);
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<AdminIndividualListItem>(
        `SELECT u.id AS user_id, ip.patient_number, u.full_name, u.phone, u.is_active,
                ip.is_job_posting_blocked, ip.block_reason, u.created_at
         FROM users u
         JOIN individual_profiles ip ON ip.user_id = u.id
         ${clause}
         ORDER BY u.created_at DESC
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM users u
         JOIN individual_profiles ip ON ip.user_id = u.id
         ${clause}`,
        params,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async findDetailByUserId(userId: string): Promise<AdminIndividualListItem | null> {
    const result = await this.db.query<AdminIndividualListItem>(
      `SELECT u.id AS user_id, ip.patient_number, u.full_name, u.phone, u.is_active,
              ip.is_job_posting_blocked, ip.block_reason, u.created_at
       FROM users u
       JOIN individual_profiles ip ON ip.user_id = u.id
       WHERE u.id = $1 AND u.role = 'individual'`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async setJobPostingBlocked(userId: string, blocked: boolean, reason: string | null): Promise<void> {
    await this.db.query(
      `UPDATE individual_profiles
       SET is_job_posting_blocked = $2, block_reason = $3, updated_at = NOW()
       WHERE user_id = $1`,
      [userId, blocked, reason],
    );
  }

  async setBlockReason(userId: string, reason: string | null): Promise<void> {
    await this.db.query(
      `UPDATE individual_profiles SET block_reason = $2, updated_at = NOW() WHERE user_id = $1`,
      [userId, reason],
    );
  }
}
