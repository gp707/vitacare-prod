import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface AdminNotesRecord {
  internal_notes: string | null;
  rate_24hrs_live_in: string | null;
  rate_12hrs_pg: string | null;
  availability_remarks: string | null;
}

export interface UpsertAdminNotesInput {
  internal_notes?: string | null;
  rate_24hrs_live_in?: number | null;
  rate_12hrs_pg?: number | null;
  availability_remarks?: string | null;
}

@Injectable()
export class AdminNotesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByProfileId(profileId: string): Promise<AdminNotesRecord | null> {
    const result = await this.db.query<AdminNotesRecord>(
      `SELECT internal_notes, rate_24hrs_live_in, rate_12hrs_pg, availability_remarks
       FROM admin_notes WHERE profile_id = $1`,
      [profileId],
    );
    return result.rows[0] ?? null;
  }

  async upsert(profileId: string, adminId: string, input: UpsertAdminNotesInput): Promise<void> {
    await this.db.query(
      `INSERT INTO admin_notes (profile_id, admin_id, internal_notes, rate_24hrs_live_in, rate_12hrs_pg, availability_remarks)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (profile_id) DO UPDATE SET
         admin_id = EXCLUDED.admin_id,
         internal_notes = EXCLUDED.internal_notes,
         rate_24hrs_live_in = EXCLUDED.rate_24hrs_live_in,
         rate_12hrs_pg = EXCLUDED.rate_12hrs_pg,
         availability_remarks = EXCLUDED.availability_remarks,
         updated_at = NOW()`,
      [
        profileId,
        adminId,
        input.internal_notes ?? null,
        input.rate_24hrs_live_in ?? null,
        input.rate_12hrs_pg ?? null,
        input.availability_remarks ?? null,
      ],
    );
  }
}
