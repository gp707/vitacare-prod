import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface ScopeOfWorkRecord {
  id: number;
  companion_care: string[];
  bedside_care: string[];
  critical_care: string[];
  updated_by: string | null;
  updated_at: Date;
}

export interface ScopeOfWorkWithUpdater extends ScopeOfWorkRecord {
  updated_by_name: string | null;
}

export interface UpdateScopeOfWorkInput {
  companion_care: string[];
  bedside_care: string[];
  critical_care: string[];
}

/** Singleton row (id fixed to 1 by a DB CHECK) — there is only ever one
 *  scope-of-work set, same convention as RateCardRepository. */
@Injectable()
export class ScopeOfWorkRepository {
  constructor(private readonly db: DatabaseService) {}

  async find(): Promise<ScopeOfWorkRecord> {
    const result = await this.db.query<ScopeOfWorkRecord>('SELECT * FROM scope_of_work WHERE id = 1');
    return result.rows[0];
  }

  async findWithUpdater(): Promise<ScopeOfWorkWithUpdater> {
    const result = await this.db.query<ScopeOfWorkWithUpdater>(
      `SELECT s.*, u.full_name AS updated_by_name
       FROM scope_of_work s
       LEFT JOIN users u ON u.id = s.updated_by
       WHERE s.id = 1`,
    );
    return result.rows[0];
  }

  async update(input: UpdateScopeOfWorkInput, adminId: string): Promise<ScopeOfWorkRecord> {
    const result = await this.db.query<ScopeOfWorkRecord>(
      `UPDATE scope_of_work
       SET companion_care = $1, bedside_care = $2, critical_care = $3, updated_by = $4, updated_at = NOW()
       WHERE id = 1
       RETURNING *`,
      [input.companion_care, input.bedside_care, input.critical_care, adminId],
    );
    return result.rows[0];
  }
}
