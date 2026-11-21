import { Injectable } from '@nestjs/common';
import { AppPlatform } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface AppMinVersionRecord {
  platform: AppPlatform;
  min_version: string;
  store_url: string | null;
  update_message: string | null;
  /** 'all' = everyone (the default); 'selected' = only the categories / accounts below. */
  audience_mode: 'all' | 'selected';
  /** caregiver | individual | hospital | rehab | clinic | agency */
  audience_categories: string[];
  audience_user_ids: string[];
  updated_by: string | null;
  updated_at: Date;
}

/** An account named in the audience, resolved for display in admin-web. */
export interface AudienceUser {
  user_id: string;
  full_name: string;
  phone: string;
  role: string;
  caregiver_number: number | null;
  patient_number: number | null;
  org_number: number | null;
  organisation_type: string | null;
}

export interface AppMinVersionWithUpdater extends AppMinVersionRecord {
  updated_by_name: string | null;
  audience_users: AudienceUser[];
}

export interface UpdateAppMinVersionInput {
  min_version: string;
  store_url?: string | null;
  update_message?: string | null;
  /** When undefined the audience is left exactly as it is. */
  audience?: {
    mode: 'all' | 'selected';
    categories: string[];
    user_ids: string[];
  };
}

@Injectable()
export class AppMinVersionsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** platform is untrusted input here (query/path param) — no matching
   *  row (including an invalid platform string) just returns null, which
   *  callers turn into GEN_002. */
  async findByPlatform(platform: string): Promise<AppMinVersionRecord | null> {
    const result = await this.db.query<AppMinVersionRecord>(
      'SELECT * FROM app_min_versions WHERE platform = $1',
      [platform],
    );
    return result.rows[0] ?? null;
  }

  async findAll(): Promise<AppMinVersionWithUpdater[]> {
    const result = await this.db.query<AppMinVersionWithUpdater>(
      `SELECT v.*, u.full_name AS updated_by_name,
              COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                         'user_id', a.id, 'full_name', a.full_name, 'phone', a.phone, 'role', a.role,
                         'caregiver_number', cp.caregiver_number, 'patient_number', ip.patient_number,
                         'org_number', op.org_number, 'organisation_type', op.organisation_type) ORDER BY a.full_name)
                FROM users a
                LEFT JOIN caregiver_profiles cp ON cp.user_id = a.id
                LEFT JOIN individual_profiles ip ON ip.user_id = a.id
                LEFT JOIN organisation_profiles op ON op.user_id = a.id
                WHERE a.id = ANY(v.audience_user_ids)
              ), '[]'::jsonb) AS audience_users
       FROM app_min_versions v
       LEFT JOIN users u ON u.id = v.updated_by
       ORDER BY v.platform`,
    );
    return result.rows;
  }

  async update(platform: string, input: UpdateAppMinVersionInput, adminId: string): Promise<AppMinVersionRecord> {
    const audience = input.audience;
    const result = await this.db.query<AppMinVersionRecord>(
      `UPDATE app_min_versions
       SET min_version = $2, store_url = $3, update_message = $4, updated_by = $5, updated_at = NOW(),
           audience_mode = COALESCE($6, audience_mode),
           audience_categories = COALESCE($7::text[], audience_categories),
           audience_user_ids = COALESCE($8::uuid[], audience_user_ids)
       WHERE platform = $1
       RETURNING *`,
      [
        platform,
        input.min_version,
        input.store_url ?? null,
        input.update_message ?? null,
        adminId,
        audience?.mode ?? null,
        audience ? audience.categories : null,
        audience ? audience.user_ids : null,
      ],
    );
    return result.rows[0];
  }

  /** Which audience category an account falls in — 'caregiver', 'individual' or its organisation type —
   *  or null for an admin / an account that no longer exists. */
  async categoryOfUser(userId: string): Promise<string | null> {
    const result = await this.db.query<{ role: string; organisation_type: string | null }>(
      `SELECT u.role, op.organisation_type
       FROM users u LEFT JOIN organisation_profiles op ON op.user_id = u.id
       WHERE u.id = $1 AND u.deleted_at IS NULL`,
      [userId],
    );
    const row = result.rows[0];
    if (!row) return null;
    if (row.role === 'caregiver' || row.role === 'individual') return row.role;
    if (row.role === 'organisation') return row.organisation_type;
    return null;
  }
}
