import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { JobApplicationStatus } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

export interface JobApplicationRecord {
  id: string;
  job_id: string;
  profile_id: string;
  status: JobApplicationStatus;
  decided_by: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface JobApplicationWithCaregiver extends JobApplicationRecord {
  full_name: string;
  phone: string;
}

@Injectable()
export class JobApplicationsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** One application per (job, caregiver) — re-applying updates in place
   *  rather than creating a duplicate row. Used only for the caregiver's
   *  own applied/rejected self-action; decided_by stays untouched here. */
  async upsert(
    jobId: string,
    profileId: string,
    status: JobApplicationStatus,
  ): Promise<JobApplicationRecord> {
    const result = await this.db.query<JobApplicationRecord>(
      `INSERT INTO job_applications (job_id, profile_id, status)
       VALUES ($1, $2, $3)
       ON CONFLICT (job_id, profile_id)
       DO UPDATE SET status = EXCLUDED.status, updated_at = NOW()
       RETURNING *`,
      [jobId, profileId, status],
    );
    return result.rows[0];
  }

  async findById(id: string): Promise<JobApplicationRecord | null> {
    const result = await this.db.query<JobApplicationRecord>(
      'SELECT * FROM job_applications WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  /** Admin decision (accept/reject) on a specific application. */
  async decide(
    id: string,
    status: JobApplicationStatus,
    adminId: string,
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE job_applications SET status = $2, decided_by = $3, updated_at = NOW() WHERE id = $1`,
      [id, status, adminId],
    );
  }

  /** The caregiver's current/most-recent accepted application, if any —
   *  used to show them their own assigned job's details even after it
   *  closes (GET /caregiver/jobs only lists active jobs). Ordered by
   *  updated_at so that if an admin's generic status-override endpoint
   *  ever unassigns a caregiver without touching this row (it doesn't
   *  cascade into job_applications), a later, more-recent acceptance on a
   *  different job still wins over the stale one. */
  async findMostRecentAcceptedByProfileId(profileId: string): Promise<JobApplicationRecord | null> {
    const result = await this.db.query<JobApplicationRecord>(
      `SELECT * FROM job_applications
       WHERE profile_id = $1 AND status = 'accepted'
       ORDER BY updated_at DESC
       LIMIT 1`,
      [profileId],
    );
    return result.rows[0] ?? null;
  }

  async findByJobId(jobId: string): Promise<JobApplicationWithCaregiver[]> {
    const result = await this.db.query<JobApplicationWithCaregiver>(
      `SELECT ja.*, u.full_name, u.phone
       FROM job_applications ja
       JOIN caregiver_profiles cp ON cp.id = ja.profile_id
       JOIN users u ON u.id = cp.user_id
       WHERE ja.job_id = $1
       ORDER BY ja.updated_at DESC`,
      [jobId],
    );
    return result.rows;
  }
}
