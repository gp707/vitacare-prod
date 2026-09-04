import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface AuditLogRetentionRecord {
  id: number;
  retention_days: number;
  updated_by: string | null;
  updated_at: Date;
}

export interface AuditLogRetentionWithUpdater extends AuditLogRetentionRecord {
  updated_by_name: string | null;
}

/** Singleton row (id fixed to 1 by a DB CHECK) — same convention as
 *  JobSettingsRepository/DutyRequirementsRepository/RateCardRepository.
 *  Admin-only: unlike those, this has no public-facing counterpart, since
 *  no caregiver/patient app ever needs to know the audit-log retention
 *  window. */
@Injectable()
export class AuditLogRetentionRepository {
  constructor(private readonly db: DatabaseService) {}

  async find(): Promise<AuditLogRetentionRecord> {
    const result = await this.db.query<AuditLogRetentionRecord>(
      'SELECT * FROM audit_log_retention_settings WHERE id = 1',
    );
    return result.rows[0];
  }

  async findWithUpdater(): Promise<AuditLogRetentionWithUpdater> {
    const result = await this.db.query<AuditLogRetentionWithUpdater>(
      `SELECT r.*, u.full_name AS updated_by_name
       FROM audit_log_retention_settings r
       LEFT JOIN users u ON u.id = r.updated_by
       WHERE r.id = 1`,
    );
    return result.rows[0];
  }

  async update(retentionDays: number, adminId: string): Promise<AuditLogRetentionRecord> {
    const result = await this.db.query<AuditLogRetentionRecord>(
      `UPDATE audit_log_retention_settings
       SET retention_days = $1, updated_by = $2, updated_at = NOW()
       WHERE id = 1
       RETURNING *`,
      [retentionDays, adminId],
    );
    return result.rows[0];
  }
}
