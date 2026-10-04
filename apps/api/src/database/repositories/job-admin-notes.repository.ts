import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface JobAdminNotesRecord {
  notes: string | null;
}

@Injectable()
export class JobAdminNotesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByJobId(jobId: string): Promise<JobAdminNotesRecord | null> {
    const result = await this.db.query<JobAdminNotesRecord>(
      `SELECT notes FROM job_admin_notes WHERE job_id = $1`,
      [jobId],
    );
    return result.rows[0] ?? null;
  }

  async upsert(jobId: string, adminId: string, notes: string | null): Promise<void> {
    await this.db.query(
      `INSERT INTO job_admin_notes (job_id, admin_id, notes)
       VALUES ($1, $2, $3)
       ON CONFLICT (job_id) DO UPDATE SET
         admin_id = EXCLUDED.admin_id,
         notes = EXCLUDED.notes,
         updated_at = NOW()`,
      [jobId, adminId, notes],
    );
  }
}
