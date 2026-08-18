import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export interface AdminIndividualListItem {
  user_id: string;
  full_name: string;
  phone: string;
  is_active: boolean;
  is_job_posting_blocked: boolean;
  block_reason: string | null;
  created_at: Date;
}

/** Admin-side view of individual (patient/family) accounts — mirrors the
 *  AdminCaregiversRepository / CaregiverProfilesRepository split: self-
 *  service lives in IndividualProfilesRepository, admin listing/block
 *  actions live here. */
@Injectable()
export class AdminIndividualsRepository {
  constructor(private readonly db: DatabaseService) {}

  async listIndividuals(page: ListPage): Promise<{ items: AdminIndividualListItem[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<AdminIndividualListItem>(
        `SELECT u.id AS user_id, u.full_name, u.phone, u.is_active,
                ip.is_job_posting_blocked, ip.block_reason, u.created_at
         FROM users u
         JOIN individual_profiles ip ON ip.user_id = u.id
         WHERE u.role = 'individual'
         ORDER BY u.created_at DESC
         LIMIT $1 OFFSET $2`,
        [page.limit, offset],
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM users u
         JOIN individual_profiles ip ON ip.user_id = u.id
         WHERE u.role = 'individual'`,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }

  async findDetailByUserId(userId: string): Promise<AdminIndividualListItem | null> {
    const result = await this.db.query<AdminIndividualListItem>(
      `SELECT u.id AS user_id, u.full_name, u.phone, u.is_active,
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
