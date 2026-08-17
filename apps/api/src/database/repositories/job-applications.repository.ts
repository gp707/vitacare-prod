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
  applied_at: Date | null;
  accepted_at: Date | null;
  rejected_at: Date | null;
  completed_at: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface JobApplicationWithCaregiver extends JobApplicationRecord {
  full_name: string;
  phone: string;
  decided_by_name: string | null;
}

@Injectable()
export class JobApplicationsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** One application per (job, caregiver) — re-applying updates in place
   *  rather than creating a duplicate row. Used only for the caregiver's
   *  own applied/rejected self-action — decided_by stays untouched (NULL,
   *  unless a fresh 'applied' clears a stale one — see below), which is
   *  exactly what lets callers tell "caregiver declined it themselves"
   *  (decided_by IS NULL) apart from "admin declined/undid it" (set). */
  async upsert(
    jobId: string,
    profileId: string,
    status: JobApplicationStatus,
  ): Promise<JobApplicationRecord> {
    if (status === JobApplicationStatus.APPLIED) {
      // A fresh 'applied' starts a new cycle — clear any accepted_at/
      // rejected_at/decided_by left over from a previous one (e.g. they
      // were rejected, the job reopened, and they applied again).
      const result = await this.db.query<JobApplicationRecord>(
        `INSERT INTO job_applications (job_id, profile_id, status, applied_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (job_id, profile_id)
         DO UPDATE SET
           status = EXCLUDED.status,
           applied_at = NOW(),
           accepted_at = NULL,
           rejected_at = NULL,
           decided_by = NULL,
           updated_at = NOW()
         RETURNING *`,
        [jobId, profileId, status],
      );
      return result.rows[0];
    }

    // Rejecting directly (no prior 'applied' row) leaves applied_at NULL —
    // they declined it outright, they never actually applied first.
    const result = await this.db.query<JobApplicationRecord>(
      `INSERT INTO job_applications (job_id, profile_id, status, rejected_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (job_id, profile_id)
       DO UPDATE SET status = EXCLUDED.status, rejected_at = NOW(), updated_at = NOW()
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

  /** Admin decision (accept/reject) on a specific application. Covers both
   *  accepting/rejecting a still-'applied' application and undoing a
   *  prior acceptance (also lands on 'rejected') — either way decided_by
   *  being set is what tells the caregiver-app "the employer decided
   *  this", not the caregiver themselves. status is only ever 'accepted'
   *  or 'rejected' here (DecideApplicationDto), so the column choice below
   *  is a fixed, non-user-controlled branch. */
  async decide(
    id: string,
    status: JobApplicationStatus,
    adminId: string,
    client?: PoolClient,
  ): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    const timestampColumn = status === JobApplicationStatus.ACCEPTED ? 'accepted_at' : 'rejected_at';
    await runner.query(
      `UPDATE job_applications SET status = $2, decided_by = $3, ${timestampColumn} = NOW(), updated_at = NOW() WHERE id = $1`,
      [id, status, adminId],
    );
  }

  /** A caregiver can only ever have one application per job — the
   *  UNIQUE(job_id, profile_id) constraint guarantees at most one row. */
  async findByJobAndProfile(jobId: string, profileId: string): Promise<JobApplicationRecord | null> {
    const result = await this.db.query<JobApplicationRecord>(
      'SELECT * FROM job_applications WHERE job_id = $1 AND profile_id = $2',
      [jobId, profileId],
    );
    return result.rows[0] ?? null;
  }

  /** Caregiver self-service "I finished this job" — distinct from an admin
   *  rejecting/undoing an acceptance, which lands on 'rejected' instead. */
  async markCompleted(id: string, client?: PoolClient): Promise<void> {
    const runner: QueryRunner = client ?? this.db;
    await runner.query(
      `UPDATE job_applications SET status = 'completed', completed_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [id],
    );
  }

  /** How many jobs this caregiver is still actively accepted onto — used
   *  right after marking one 'completed' to decide whether any others
   *  remain (if none, verification_status can drop back to 'available'). */
  async countAcceptedByProfileId(profileId: string, client?: PoolClient): Promise<number> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<{ count: string }>(
      `SELECT COUNT(*) FROM job_applications WHERE profile_id = $1 AND status = 'accepted'`,
      [profileId],
    );
    return Number(result.rows[0].count);
  }

  async findByJobId(jobId: string): Promise<JobApplicationWithCaregiver[]> {
    const result = await this.db.query<JobApplicationWithCaregiver>(
      `SELECT ja.*, u.full_name, u.phone, decider.full_name AS decided_by_name
       FROM job_applications ja
       JOIN caregiver_profiles cp ON cp.id = ja.profile_id
       JOIN users u ON u.id = cp.user_id
       LEFT JOIN users decider ON decider.id = ja.decided_by
       WHERE ja.job_id = $1
       ORDER BY ja.updated_at DESC`,
      [jobId],
    );
    return result.rows;
  }
}
