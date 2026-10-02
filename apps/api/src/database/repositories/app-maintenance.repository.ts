import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface AppMaintenanceRecord {
  enabled: boolean;
  message: string | null;
  updated_by: string | null;
  updated_at: Date;
}

export interface AppMaintenanceWithUpdater extends AppMaintenanceRecord {
  updated_by_name: string | null;
}

export interface UpdateAppMaintenanceInput {
  enabled: boolean;
  message?: string | null;
}

/** Singleton row (id fixed to 1 by a DB CHECK), same convention as
 *  rate_card/scope_of_work/duty_requirements — one JustHeal binary now
 *  covers both the caregiver and patient/hospital flows, so there's only
 *  one app to take down for maintenance, not two independent ones. */
@Injectable()
export class AppMaintenanceRepository {
  constructor(private readonly db: DatabaseService) {}

  async find(): Promise<AppMaintenanceRecord | null> {
    const result = await this.db.query<AppMaintenanceRecord>('SELECT * FROM app_maintenance WHERE id = 1');
    return result.rows[0] ?? null;
  }

  async findWithUpdater(): Promise<AppMaintenanceWithUpdater | null> {
    const result = await this.db.query<AppMaintenanceWithUpdater>(
      `SELECT m.*, u.full_name AS updated_by_name
       FROM app_maintenance m
       LEFT JOIN users u ON u.id = m.updated_by
       WHERE m.id = 1`,
    );
    return result.rows[0] ?? null;
  }

  async update(input: UpdateAppMaintenanceInput, adminId: string): Promise<AppMaintenanceRecord> {
    const result = await this.db.query<AppMaintenanceRecord>(
      `UPDATE app_maintenance
       SET enabled = $1, message = $2, updated_by = $3, updated_at = NOW()
       WHERE id = 1
       RETURNING *`,
      [input.enabled, input.message ?? null, adminId],
    );
    return result.rows[0];
  }
}
