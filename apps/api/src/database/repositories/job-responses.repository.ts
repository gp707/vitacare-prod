import { Injectable } from '@nestjs/common';
import { JobResponse } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface JobResponseRecord {
  id: string;
  job_id: string;
  profile_id: string;
  response: JobResponse;
  message: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface JobResponseWithCaregiver extends JobResponseRecord {
  full_name: string;
  phone: string;
}

@Injectable()
export class JobResponsesRepository {
  constructor(private readonly db: DatabaseService) {}

  /** One response per (job, caregiver) — re-responding updates in place
   *  rather than creating a duplicate row (SPEC.md 6.6). */
  async upsert(
    jobId: string,
    profileId: string,
    response: JobResponse,
    message: string | null,
  ): Promise<JobResponseRecord> {
    const result = await this.db.query<JobResponseRecord>(
      `INSERT INTO job_responses (job_id, profile_id, response, message)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (job_id, profile_id)
       DO UPDATE SET response = EXCLUDED.response, message = EXCLUDED.message, updated_at = NOW()
       RETURNING *`,
      [jobId, profileId, response, message],
    );
    return result.rows[0];
  }

  async findByJobId(jobId: string): Promise<JobResponseWithCaregiver[]> {
    const result = await this.db.query<JobResponseWithCaregiver>(
      `SELECT jr.*, u.full_name, u.phone
       FROM job_responses jr
       JOIN caregiver_profiles cp ON cp.id = jr.profile_id
       JOIN users u ON u.id = cp.user_id
       WHERE jr.job_id = $1
       ORDER BY jr.updated_at DESC`,
      [jobId],
    );
    return result.rows;
  }
}
