import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface PausePeriod {
  /** First paused day (YYYY-MM-DD). */
  from: string;
  /** The day it was resumed (exclusive: that day is a working day), or null while still paused. */
  to: string | null;
}

export interface LeaveState {
  leave_dates: string[];
  pauses: PausePeriod[];
}

/** SQL fragments that add `leave_dates` / `pauses` to any query that has the
 *  applications table aliased as [alias] — used for the caregiver's own
 *  `my_application` and the patient's applicant list, so both sides read the
 *  same shape. Dates come back as YYYY-MM-DD strings. */
export const leaveDatesSql = (alias: string): string =>
  `COALESCE((SELECT jsonb_agg(l.leave_date ORDER BY l.leave_date) FROM job_application_leaves l WHERE l.application_id = ${alias}.id), '[]'::jsonb)`;

export const pausesSql = (alias: string): string =>
  `COALESCE((SELECT jsonb_agg(jsonb_build_object('from', p.paused_from, 'to', p.resumed_on) ORDER BY p.paused_from) FROM job_application_pauses p WHERE p.application_id = ${alias}.id), '[]'::jsonb)`;

/** Leave days and salary pauses of one accepted caregiver on one job
 *  (migration 093). Set by the patient/family; seen by both sides. */
@Injectable()
export class JobApplicationLeavesRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Marks [dates] (YYYY-MM-DD) as leave. Returns only the days that were not
   *  already marked, so a repeat tap doesn't notify the caregiver twice. */
  async addLeaves(applicationId: string, dates: string[]): Promise<string[]> {
    const result = await this.db.query<{ leave_date: string }>(
      `INSERT INTO job_application_leaves (application_id, leave_date)
       SELECT $1, d::date FROM unnest($2::text[]) AS d
       ON CONFLICT DO NOTHING
       RETURNING leave_date::text`,
      [applicationId, dates],
    );
    return result.rows.map((row) => row.leave_date).sort();
  }

  /** Cancels one marked day. False when that day was not marked. */
  async removeLeave(applicationId: string, date: string): Promise<boolean> {
    const result = await this.db.query(
      `DELETE FROM job_application_leaves WHERE application_id = $1 AND leave_date = $2::date`,
      [applicationId, date],
    );
    return (result.rowCount ?? 0) > 0;
  }

  async getState(applicationId: string): Promise<LeaveState> {
    const result = await this.db.query<LeaveState>(
      `SELECT ${leaveDatesSql('ja')} AS leave_dates, ${pausesSql('ja')} AS pauses
       FROM job_applications ja WHERE ja.id = $1`,
      [applicationId],
    );
    return result.rows[0] ?? { leave_dates: [], pauses: [] };
  }
}
