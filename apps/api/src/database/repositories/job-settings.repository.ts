import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface JobSettingsRecord {
  id: number;
  apply_by_window_days: number;
  updated_by: string | null;
  updated_at: Date;
}

export interface JobSettingsWithUpdater extends JobSettingsRecord {
  updated_by_name: string | null;
}

/** Singleton row (id fixed to 1 by a DB CHECK) — same convention as
 *  DutyRequirementsRepository/ScopeOfWorkRepository/RateCardRepository.
 *  Currently holds just apply_by_window_days (the caregiver-facing
 *  "apply-by" urgency window on a job — see JobModel.applyByDate/
 *  daysLeftToApply — previously a hardcoded 3-day constant, now
 *  admin-configurable), but is the general home for future admin-web
 *  Settings additions, not a single-purpose table. */
@Injectable()
export class JobSettingsRepository {
  constructor(private readonly db: DatabaseService) {}

  async find(): Promise<JobSettingsRecord> {
    const result = await this.db.query<JobSettingsRecord>('SELECT * FROM job_settings WHERE id = 1');
    return result.rows[0];
  }

  async findWithUpdater(): Promise<JobSettingsWithUpdater> {
    const result = await this.db.query<JobSettingsWithUpdater>(
      `SELECT j.*, u.full_name AS updated_by_name
       FROM job_settings j
       LEFT JOIN users u ON u.id = j.updated_by
       WHERE j.id = 1`,
    );
    return result.rows[0];
  }

  async update(applyByWindowDays: number, adminId: string): Promise<JobSettingsRecord> {
    const result = await this.db.query<JobSettingsRecord>(
      `UPDATE job_settings
       SET apply_by_window_days = $1, updated_by = $2, updated_at = NOW()
       WHERE id = 1
       RETURNING *`,
      [applyByWindowDays, adminId],
    );
    return result.rows[0];
  }
}
