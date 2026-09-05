import { Injectable } from '@nestjs/common';
import { LoginApp } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface AppMaintenanceRecord {
  app: LoginApp;
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

@Injectable()
export class AppMaintenanceRepository {
  constructor(private readonly db: DatabaseService) {}

  /** app is untrusted input here (query param / path param) — no matching
   *  row (including an invalid app string) just returns null, which
   *  callers turn into GEN_002. */
  async findByApp(app: string): Promise<AppMaintenanceRecord | null> {
    const result = await this.db.query<AppMaintenanceRecord>(
      'SELECT * FROM app_maintenance WHERE app = $1',
      [app],
    );
    return result.rows[0] ?? null;
  }

  async findAll(): Promise<AppMaintenanceWithUpdater[]> {
    const result = await this.db.query<AppMaintenanceWithUpdater>(
      `SELECT m.*, u.full_name AS updated_by_name
       FROM app_maintenance m
       LEFT JOIN users u ON u.id = m.updated_by
       ORDER BY m.app`,
    );
    return result.rows;
  }

  async update(app: string, input: UpdateAppMaintenanceInput, adminId: string): Promise<AppMaintenanceRecord> {
    const result = await this.db.query<AppMaintenanceRecord>(
      `UPDATE app_maintenance
       SET enabled = $2, message = $3, updated_by = $4, updated_at = NOW()
       WHERE app = $1
       RETURNING *`,
      [app, input.enabled, input.message ?? null, adminId],
    );
    return result.rows[0];
  }
}
