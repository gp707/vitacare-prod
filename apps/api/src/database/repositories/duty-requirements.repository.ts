import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface DutyRequirementsRecord {
  id: number;
  live_in: string[];
  day_duty: string[];
  night_duty: string[];
  updated_by: string | null;
  updated_at: Date;
}

export interface DutyRequirementsWithUpdater extends DutyRequirementsRecord {
  updated_by_name: string | null;
}

export interface UpdateDutyRequirementsInput {
  live_in: string[];
  day_duty: string[];
  night_duty: string[];
}

/** Singleton row (id fixed to 1 by a DB CHECK) — there is only ever one
 *  duty-requirements set, same convention as ScopeOfWorkRepository/
 *  RateCardRepository. Lists what a patient/family must arrange for the
 *  nurse under each of the 3 fixed Duty Type shifts (bedding/meals/
 *  supplies, no cooking or chores, etc.) — a wholly separate concept from
 *  scope_of_work (which describes caregiving TASKS by care tier, not what
 *  the family must ARRANGE by shift). */
@Injectable()
export class DutyRequirementsRepository {
  constructor(private readonly db: DatabaseService) {}

  async find(): Promise<DutyRequirementsRecord> {
    const result = await this.db.query<DutyRequirementsRecord>('SELECT * FROM duty_requirements WHERE id = 1');
    return result.rows[0];
  }

  async findWithUpdater(): Promise<DutyRequirementsWithUpdater> {
    const result = await this.db.query<DutyRequirementsWithUpdater>(
      `SELECT d.*, u.full_name AS updated_by_name
       FROM duty_requirements d
       LEFT JOIN users u ON u.id = d.updated_by
       WHERE d.id = 1`,
    );
    return result.rows[0];
  }

  async update(input: UpdateDutyRequirementsInput, adminId: string): Promise<DutyRequirementsRecord> {
    const result = await this.db.query<DutyRequirementsRecord>(
      `UPDATE duty_requirements
       SET live_in = $1, day_duty = $2, night_duty = $3, updated_by = $4, updated_at = NOW()
       WHERE id = 1
       RETURNING *`,
      [input.live_in, input.day_duty, input.night_duty, adminId],
    );
    return result.rows[0];
  }
}
