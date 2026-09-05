import { Injectable } from '@nestjs/common';
import { AppPlatform, LoginApp } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface AppMinVersionRecord {
  app: LoginApp;
  platform: AppPlatform;
  min_version: string;
  store_url: string | null;
  update_message: string | null;
  updated_by: string | null;
  updated_at: Date;
}

export interface AppMinVersionWithUpdater extends AppMinVersionRecord {
  updated_by_name: string | null;
}

export interface UpdateAppMinVersionInput {
  min_version: string;
  store_url?: string | null;
  update_message?: string | null;
}

@Injectable()
export class AppMinVersionsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** app/platform are untrusted input here (query params / path params) —
   *  no matching row (including an invalid app or platform string) just
   *  returns null, which callers turn into GEN_002. */
  async findByAppAndPlatform(app: string, platform: string): Promise<AppMinVersionRecord | null> {
    const result = await this.db.query<AppMinVersionRecord>(
      'SELECT * FROM app_min_versions WHERE app = $1 AND platform = $2',
      [app, platform],
    );
    return result.rows[0] ?? null;
  }

  async findAll(): Promise<AppMinVersionWithUpdater[]> {
    const result = await this.db.query<AppMinVersionWithUpdater>(
      `SELECT v.*, u.full_name AS updated_by_name
       FROM app_min_versions v
       LEFT JOIN users u ON u.id = v.updated_by
       ORDER BY v.app, v.platform`,
    );
    return result.rows;
  }

  async update(
    app: string,
    platform: string,
    input: UpdateAppMinVersionInput,
    adminId: string,
  ): Promise<AppMinVersionRecord> {
    const result = await this.db.query<AppMinVersionRecord>(
      `UPDATE app_min_versions
       SET min_version = $3, store_url = $4, update_message = $5, updated_by = $6, updated_at = NOW()
       WHERE app = $1 AND platform = $2
       RETURNING *`,
      [app, platform, input.min_version, input.store_url ?? null, input.update_message ?? null, adminId],
    );
    return result.rows[0];
  }
}
