import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export interface TicketRecord {
  id: string;
  user_id: string;
  type: 'forgot_pin';
  status: 'open' | 'resolved';
  phone: string;
  notes: string | null;
  created_at: Date;
  resolved_at: Date | null;
  resolved_by: string | null;
}

/** Resolved for admin-web's list — same "resolve a user_id's role-specific
 *  display id" join pattern as AuditLogsRepository's target resolution
 *  (see CLAUDE.md's Audit Logs note): a ticket's user is exactly one of
 *  caregiver/individual/organisation, so at most one of
 *  caregiver_number/patient_number/org_number is ever non-null. */
export interface TicketListItem extends TicketRecord {
  user_full_name: string;
  user_role: string;
  caregiver_number: number | null;
  caregiver_profile_id: string | null;
  patient_number: number | null;
  org_number: number | null;
  resolved_by_name: string | null;
}

const TICKET_JOINS = `
  JOIN users u ON u.id = t.user_id
  LEFT JOIN caregiver_profiles cp ON cp.user_id = t.user_id
  LEFT JOIN individual_profiles ip ON ip.user_id = t.user_id
  LEFT JOIN organisation_profiles op ON op.user_id = t.user_id
  LEFT JOIN users resolver ON resolver.id = t.resolved_by
`;

export interface TicketListFilters {
  status?: 'open' | 'resolved';
}

@Injectable()
export class TicketsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(userId: string, type: 'forgot_pin', phone: string): Promise<TicketRecord> {
    const result = await this.db.query<TicketRecord>(
      `INSERT INTO support_tickets (user_id, type, phone) VALUES ($1, $2, $3) RETURNING *`,
      [userId, type, phone],
    );
    return result.rows[0];
  }

  /** Used to dedupe — a user who taps "Forgot PIN" again while their last
   *  one is still open gets pointed at the existing ticket rather than
   *  accumulating duplicates. */
  async findOpenByUserAndType(userId: string, type: 'forgot_pin'): Promise<TicketRecord | null> {
    const result = await this.db.query<TicketRecord>(
      `SELECT * FROM support_tickets WHERE user_id = $1 AND type = $2 AND status = 'open' LIMIT 1`,
      [userId, type],
    );
    return result.rows[0] ?? null;
  }

  async findById(id: string): Promise<TicketRecord | null> {
    const result = await this.db.query<TicketRecord>(`SELECT * FROM support_tickets WHERE id = $1`, [id]);
    return result.rows[0] ?? null;
  }

  /** Only a still-open ticket can be resolved — returns null (not an
   *  exception) otherwise, same convention as
   *  AdminPushNotificationsRepository.cancel. */
  async resolve(id: string, adminId: string, notes: string | null): Promise<TicketRecord | null> {
    const result = await this.db.query<TicketRecord>(
      `UPDATE support_tickets
       SET status = 'resolved', resolved_at = NOW(), resolved_by = $2, notes = $3
       WHERE id = $1 AND status = 'open'
       RETURNING *`,
      [id, adminId, notes],
    );
    return result.rows[0] ?? null;
  }

  async list(filters: TicketListFilters, page: ListPage): Promise<{ items: TicketListItem[]; total: number }> {
    const conditions: string[] = [];
    const params: unknown[] = [];
    if (filters.status) {
      params.push(filters.status);
      conditions.push(`t.status = $${params.length}`);
    }
    const clause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const offset = (page.page - 1) * page.limit;
    const listParams = [...params, page.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<TicketListItem>(
        `SELECT t.*, u.full_name AS user_full_name, u.role AS user_role,
                cp.caregiver_number, cp.id AS caregiver_profile_id,
                ip.patient_number, op.org_number,
                resolver.full_name AS resolved_by_name
         FROM support_tickets t
         ${TICKET_JOINS}
         ${clause}
         ORDER BY t.created_at DESC
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(
        `SELECT COUNT(*) FROM support_tickets t ${clause}`,
        params,
      ),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }
}
