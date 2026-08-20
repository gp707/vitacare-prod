import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export interface AdminOrganisationListItem {
  user_id: string;
  org_number: number;
  full_name: string;
  phone: string;
  organisation_name: string;
  organisation_type: string;
  city: string;
  area: string;
  is_active: boolean;
  is_job_posting_blocked: boolean;
  block_reason: string | null;
  created_at: Date;
}

export interface AdminOrganisationListFilters {
  /** Matches organisation_name, contact full_name, phone, or the display id
   *  (ORG-<n>). */
  search?: string;
  blockStatus?: 'active' | 'job_posting_blocked' | 'blocked';
  organisationType?: string;
  city?: string;
}

function buildOrganisationsWhereClause(filters: AdminOrganisationListFilters): {
  clause: string;
  params: unknown[];
} {
  const conditions = [`u.role = 'organisation'`];
  const params: unknown[] = [];
  if (filters.search) {
    params.push(`%${filters.search}%`);
    conditions.push(
      `(op.organisation_name ILIKE $${params.length} OR u.full_name ILIKE $${params.length}
        OR u.phone ILIKE $${params.length} OR ('ORG-' || op.org_number::text) ILIKE $${params.length})`,
    );
  }
  if (filters.blockStatus === 'blocked') {
    conditions.push(`u.is_active = false`);
  } else if (filters.blockStatus === 'job_posting_blocked') {
    conditions.push(`u.is_active = true AND op.is_job_posting_blocked = true`);
  } else if (filters.blockStatus === 'active') {
    conditions.push(`u.is_active = true AND op.is_job_posting_blocked = false`);
  }
  if (filters.organisationType) {
    params.push(filters.organisationType);
    conditions.push(`op.organisation_type = $${params.length}`);
  }
  if (filters.city) {
    params.push(filters.city);
    conditions.push(`op.city = $${params.length}`);
  }
  return { clause: `WHERE ${conditions.join(' AND ')}`, params };
}

/** Admin-side view of organisation (hospital/rehab/clinic) accounts —
 *  mirrors AdminIndividualsRepository exactly. Self-service lives in
 *  OrganisationProfilesRepository; admin listing/block actions live here. */
@Injectable()
export class AdminOrganisationsRepository {
  constructor(private readonly db: DatabaseService) {}

  async listOrganisations(
    filters: AdminOrganisationListFilters,
    page: ListPage,
  ): Promise<{ items: AdminOrganisationListItem[]; total: number }> {
    const { clause, params } = buildOrganisationsWhereClause(filters);
    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<AdminOrganisationListItem>(
        `SELECT u.id AS user_id, op.org_number, u.full_name, u.phone,
                op.organisation_name, op.organisation_type, op.city, op.area,
                u.is_active, op.is_job_posting_blocked, op.block_reason, u.created_at
         FROM users u
         JOIN organisation_profiles op ON op.user_id = u.id
         ${clause}
         ORDER BY u.created_at DESC
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM users u
         JOIN organisation_profiles op ON op.user_id = u.id
         ${clause}`,
        params,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async findDetailByUserId(userId: string): Promise<AdminOrganisationListItem | null> {
    const result = await this.db.query<AdminOrganisationListItem>(
      `SELECT u.id AS user_id, op.org_number, u.full_name, u.phone,
              op.organisation_name, op.organisation_type, op.city, op.area,
              u.is_active, op.is_job_posting_blocked, op.block_reason, u.created_at
       FROM users u
       JOIN organisation_profiles op ON op.user_id = u.id
       WHERE u.id = $1 AND u.role = 'organisation'`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async setJobPostingBlocked(userId: string, blocked: boolean, reason: string | null): Promise<void> {
    await this.db.query(
      `UPDATE organisation_profiles
       SET is_job_posting_blocked = $2, block_reason = $3, updated_at = NOW()
       WHERE user_id = $1`,
      [userId, blocked, reason],
    );
  }

  async setBlockReason(userId: string, reason: string | null): Promise<void> {
    await this.db.query(
      `UPDATE organisation_profiles SET block_reason = $2, updated_at = NOW() WHERE user_id = $1`,
      [userId, reason],
    );
  }

  /** Admin override — only fields present (not undefined) on `input` are
   *  written. Keyed on user_id (unlike caregiver_profiles' adminUpdate,
   *  which is keyed on the profile's own id) since that's what every
   *  other method on this repository already keys on. */
  async adminUpdate(
    userId: string,
    input: {
      organisation_name?: string;
      contact_person_name?: string;
      organisation_type?: string;
      city?: string;
      area?: string;
    },
  ): Promise<void> {
    const entries = Object.entries(input).filter(([, value]) => value !== undefined);
    if (entries.length === 0) return;

    const setClauses = entries.map(([key], i) => `${key} = $${i + 2}`);
    const values = entries.map(([, value]) => value);
    await this.db.query(
      `UPDATE organisation_profiles SET ${setClauses.join(', ')}, updated_at = NOW() WHERE user_id = $1`,
      [userId, ...values],
    );
  }
}
