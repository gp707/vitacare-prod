import { Injectable } from '@nestjs/common';
import { LoginApp } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface OtpAuthSettingRecord {
  app: LoginApp;
  enabled: boolean;
  updated_by: string | null;
  updated_at: Date;
}

export interface OtpAuthSettingWithUpdater extends OtpAuthSettingRecord {
  updated_by_name: string | null;
}

@Injectable()
export class OtpAuthSettingsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** app is untrusted input here in some callers (query param) — no
   *  matching row (including an invalid app string) just returns null. */
  async findByApp(app: string): Promise<OtpAuthSettingRecord | null> {
    const result = await this.db.query<OtpAuthSettingRecord>(
      'SELECT * FROM otp_auth_settings WHERE app = $1',
      [app],
    );
    return result.rows[0] ?? null;
  }

  async findAll(): Promise<OtpAuthSettingWithUpdater[]> {
    const result = await this.db.query<OtpAuthSettingWithUpdater>(
      `SELECT s.*, u.full_name AS updated_by_name
       FROM otp_auth_settings s
       LEFT JOIN users u ON u.id = s.updated_by
       ORDER BY s.app`,
    );
    return result.rows;
  }

  async update(app: string, enabled: boolean, adminId: string): Promise<OtpAuthSettingRecord> {
    const result = await this.db.query<OtpAuthSettingRecord>(
      `UPDATE otp_auth_settings
       SET enabled = $2, updated_by = $3, updated_at = NOW()
       WHERE app = $1
       RETURNING *`,
      [app, enabled, adminId],
    );
    return result.rows[0];
  }
}
