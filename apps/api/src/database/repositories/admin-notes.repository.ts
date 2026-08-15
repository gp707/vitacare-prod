import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface AdminNotesRecord {
  internal_notes: string | null;
  availability_remarks: string | null;
}

export interface UpsertAdminNotesInput {
  internal_notes?: string | null;
  availability_remarks?: string | null;
}

@Injectable()
export class AdminNotesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByProfileId(profileId: string): Promise<AdminNotesRecord | null> {
    const result = await this.db.query<AdminNotesRecord>(
      `SELECT internal_notes, availability_remarks
       FROM admin_notes WHERE profile_id = $1`,
      [profileId],
    );
    return result.rows[0] ?? null;
  }

  async upsert(profileId: string, adminId: string, input: UpsertAdminNotesInput): Promise<void> {
    await this.db.query(
      `INSERT INTO admin_notes (profile_id, admin_id, internal_notes, availability_remarks)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (profile_id) DO UPDATE SET
         admin_id = EXCLUDED.admin_id,
         internal_notes = EXCLUDED.internal_notes,
         availability_remarks = EXCLUDED.availability_remarks,
         updated_at = NOW()`,
      [profileId, adminId, input.internal_notes ?? null, input.availability_remarks ?? null],
    );
  }
}
