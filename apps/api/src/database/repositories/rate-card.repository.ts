import { Injectable } from '@nestjs/common';
import { FrequencyOfCare } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface RateCardRecord {
  frequency_of_care: FrequencyOfCare;
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

/** One row per frequency ('daily'/'monthly', a DB CHECK) — same "one row
 *  per key" convention as AppMinVersionsRepository (platform). */
@Injectable()
export class RateCardRepository {
  constructor(private readonly db: DatabaseService) {}

  /** frequency is untrusted input here (path param on the public
   *  endpoint's admin counterpart) — no matching row just returns null,
   *  which callers turn into GEN_002. */
  async findByFrequency(frequency: string): Promise<RateCardRecord | null> {
    const result = await this.db.query<RateCardRecord>(
      'SELECT * FROM rate_card WHERE frequency_of_care = $1',
      [frequency],
    );
    return result.rows[0] ?? null;
  }

  /** Public — both caregiver-app and nursenow-app fetch this once and show
   *  both cards behind the same persistent app-bar button. */
  async findAll(): Promise<RateCardRecord[]> {
    const result = await this.db.query<RateCardRecord>(
      'SELECT * FROM rate_card ORDER BY frequency_of_care',
    );
    return result.rows;
  }

  async findAllWithUpdater(): Promise<RateCardWithUpdater[]> {
    const result = await this.db.query<RateCardWithUpdater>(
      `SELECT r.*, u.full_name AS updated_by_name
       FROM rate_card r
       LEFT JOIN users u ON u.id = r.updated_by
       ORDER BY r.frequency_of_care`,
    );
    return result.rows;
  }

  async update(frequency: string, input: UpdateRateCardInput, adminId: string): Promise<RateCardRecord> {
    const result = await this.db.query<RateCardRecord>(
      `UPDATE rate_card
       SET title = $2, column_labels = $3, row_labels = $4, cells = $5, updated_by = $6, updated_at = NOW()
       WHERE frequency_of_care = $1
       RETURNING *`,
      [frequency, input.title, input.column_labels, input.row_labels, JSON.stringify(input.cells), adminId],
    );
    return result.rows[0];
  }
}
