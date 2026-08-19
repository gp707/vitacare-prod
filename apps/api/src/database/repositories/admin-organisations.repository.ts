import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export interface AdminOrganisationListItem {
  user_id: string;
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

/** Admin-side view of organisation (hospital/rehab/clinic) accounts —
 *  mirrors AdminIndividualsRepository exactly. Self-service lives in
 *  OrganisationProfilesRepository; admin listing/block actions live here. */
@Injectable()
export class AdminOrganisationsRepository {
  constructor(private readonly db: DatabaseService) {}

  async listOrganisations(page: ListPage): Promise<{ items: AdminOrganisationListItem[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<AdminOrganisationListItem>(
        `SELECT u.id AS user_id, u.full_name, u.phone,
                op.organisation_name, op.organisation_type, op.city, op.area,
                u.is_active, op.is_job_posting_blocked, op.block_reason, u.created_at
         FROM users u
         JOIN organisation_profiles op ON op.user_id = u.id
         WHERE u.role = 'organisation'
         ORDER BY u.created_at DESC
         LIMIT $1 OFFSET $2`,
        [page.limit, offset],
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM users u
         JOIN organisation_profiles op ON op.user_id = u.id
         WHERE u.role = 'organisation'`,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async findDetailByUserId(userId: string): Promise<AdminOrganisationListItem | null> {
    const result = await this.db.query<AdminOrganisationListItem>(
      `SELECT u.id AS user_id, u.full_name, u.phone,
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
}
