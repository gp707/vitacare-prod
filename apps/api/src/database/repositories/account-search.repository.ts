import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface AccountSearchItem {
  user_id: string;
  full_name: string;
  phone: string;
  /** caregiver | individual | organisation */
  role: string;
  caregiver_number: number | null;
  patient_number: number | null;
  org_number: number | null;
  /** hospital | rehab | clinic | agency — organisations only. */
  organisation_type: string | null;
  organisation_name: string | null;
}

/** A light search over caregiver / patient / organisation accounts, used by admin pickers (for example
 *  choosing the specific accounts a forced app version applies to). */
@Injectable()
export class AccountSearchRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Matches name, phone, organisation name and the NUR-/PAT-/ORG- ids. [category] narrows to one
   *  audience category ('caregiver', 'individual' or an organisation type). Never returns deleted
   *  accounts; at most [limit] rows. */
  async search(query: string, category: string | null, limit = 20): Promise<AccountSearchItem[]> {
    const like = `%${query.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    const result = await this.db.query<AccountSearchItem>(
      `SELECT u.id AS user_id, u.full_name, u.phone, u.role,
              cp.caregiver_number, ip.patient_number, op.org_number,
              op.organisation_type, op.organisation_name
       FROM users u
       LEFT JOIN caregiver_profiles cp ON cp.user_id = u.id
       LEFT JOIN individual_profiles ip ON ip.user_id = u.id
       LEFT JOIN organisation_profiles op ON op.user_id = u.id
       WHERE u.role IN ('caregiver', 'individual', 'organisation') AND u.deleted_at IS NULL
         AND (u.full_name ILIKE $1 OR u.phone ILIKE $1 OR op.organisation_name ILIKE $1
              OR ('NUR-' || cp.caregiver_number::text) ILIKE $1
              OR ('PAT-' || ip.patient_number::text) ILIKE $1
              OR ('ORG-' || op.org_number::text) ILIKE $1)
         AND ($2::text IS NULL OR (CASE WHEN u.role = 'organisation' THEN op.organisation_type ELSE u.role END) = $2)
       ORDER BY u.created_at DESC
       LIMIT $3`,
      [like, category, limit],
    );
    return result.rows;
  }

  /** How many of [ids] are existing, non-deleted caregiver/patient/organisation accounts. */
  async countExisting(ids: string[]): Promise<number> {
    if (ids.length === 0) return 0;
    const result = await this.db.query<{ count: string }>(
      `SELECT COUNT(*) FROM users
       WHERE id = ANY($1::uuid[]) AND role IN ('caregiver', 'individual', 'organisation') AND deleted_at IS NULL`,
      [ids],
    );
    return Number(result.rows[0].count);
  }
}
