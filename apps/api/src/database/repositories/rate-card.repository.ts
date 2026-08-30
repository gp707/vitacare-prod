import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface RateCardRecord {
  id: number;
  title: string;
  column_labels: string[];
  row_labels: string[];
  cells: string[][];
  updated_by: string | null;
  updated_at: Date;
}

export interface RateCardWithUpdater extends RateCardRecord {
  updated_by_name: string | null;
}

export interface UpdateRateCardInput {
  title: string;
  column_labels: string[];
  row_labels: string[];
  cells: string[][];
}

/** Singleton row (id fixed to 1 by a DB CHECK) — there is only ever one
 *  rate card, so every method operates on that one row. */
@Injectable()
export class RateCardRepository {
  constructor(private readonly db: DatabaseService) {}

  async find(): Promise<RateCardRecord> {
    const result = await this.db.query<RateCardRecord>('SELECT * FROM rate_card WHERE id = 1');
    return result.rows[0];
  }

  async findWithUpdater(): Promise<RateCardWithUpdater> {
    const result = await this.db.query<RateCardWithUpdater>(
      `SELECT r.*, u.full_name AS updated_by_name
       FROM rate_card r
       LEFT JOIN users u ON u.id = r.updated_by
       WHERE r.id = 1`,
    );
    return result.rows[0];
  }

  async update(input: UpdateRateCardInput, adminId: string): Promise<RateCardRecord> {
    const result = await this.db.query<RateCardRecord>(
      `UPDATE rate_card
       SET title = $1, column_labels = $2, row_labels = $3, cells = $4, updated_by = $5, updated_at = NOW()
       WHERE id = 1
       RETURNING *`,
      [input.title, input.column_labels, input.row_labels, JSON.stringify(input.cells), adminId],
    );
    return result.rows[0];
  }
}
