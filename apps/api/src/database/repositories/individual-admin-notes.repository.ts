import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface IndividualAdminNotesRecord {
  notes: string | null;
}

@Injectable()
export class IndividualAdminNotesRepository {
  constructor(private readonly db: DatabaseService) {}

  async findByUserId(userId: string): Promise<IndividualAdminNotesRecord | null> {
    const result = await this.db.query<IndividualAdminNotesRecord>(
      `SELECT notes FROM individual_admin_notes WHERE user_id = $1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async upsert(userId: string, adminId: string, notes: string | null): Promise<void> {
    await this.db.query(
      `INSERT INTO individual_admin_notes (user_id, admin_id, notes)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id) DO UPDATE SET
         admin_id = EXCLUDED.admin_id,
         notes = EXCLUDED.notes,
         updated_at = NOW()`,
      [userId, adminId, notes],
    );
  }
}
