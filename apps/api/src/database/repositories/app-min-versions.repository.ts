import { Injectable } from '@nestjs/common';
import { AppPlatform } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface AppMinVersionRecord {
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

  /** platform is untrusted input here (query param / path param) — no
   *  matching row (including an invalid platform string) just returns
   *  null, which callers turn into GEN_002. */
  async findByPlatform(platform: string): Promise<AppMinVersionRecord | null> {
    const result = await this.db.query<AppMinVersionRecord>(
      'SELECT * FROM app_min_versions WHERE platform = $1',
      [platform],
    );
    return result.rows[0] ?? null;
  }

  async findAll(): Promise<AppMinVersionWithUpdater[]> {
    const result = await this.db.query<AppMinVersionWithUpdater>(
      `SELECT v.*, u.full_name AS updated_by_name
       FROM app_min_versions v
       LEFT JOIN users u ON u.id = v.updated_by
       ORDER BY v.platform`,
    );
    return result.rows;
  }

  async update(
    platform: string,
    input: UpdateAppMinVersionInput,
    adminId: string,
  ): Promise<AppMinVersionRecord> {
    const result = await this.db.query<AppMinVersionRecord>(
      `UPDATE app_min_versions
       SET min_version = $2, store_url = $3, update_message = $4, updated_by = $5, updated_at = NOW()
       WHERE platform = $1
       RETURNING *`,
      [platform, input.min_version, input.store_url ?? null, input.update_message ?? null, adminId],
    );
    return result.rows[0];
  }
}
