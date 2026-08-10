import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { DatabaseService } from '../database.service';

export interface AuditLogListItem {
  id: string;
  user_id: string | null;
  user_name: string | null;
  target_user_id: string | null;
  target_user_name: string | null;
  action: AuditAction;
  entity_type: string;
  entity_id: string | null;
  before_value: Record<string, unknown> | null;
  after_value: Record<string, unknown> | null;
  ip_address: string | null;
  created_at: Date;
}

export interface AuditLogListFilters {
  userId?: string;
  targetUserId?: string;
  action?: AuditAction;
  fromDate?: string;
  toDate?: string;
}

export interface AuditLogListSort {
  order: 'asc' | 'desc';
  page: number;
  limit: number;
}

function buildWhereClause(filters: AuditLogListFilters): { clause: string; params: unknown[] } {
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (filters.userId) {
    params.push(filters.userId);
    conditions.push(`al.user_id = $${params.length}`);
  }
  if (filters.targetUserId) {
    params.push(filters.targetUserId);
    conditions.push(`al.target_user_id = $${params.length}`);
  }
  if (filters.action) {
    params.push(filters.action);
    conditions.push(`al.action = $${params.length}`);
  }
  if (filters.fromDate) {
    params.push(filters.fromDate);
    conditions.push(`al.created_at >= $${params.length}`);
  }
  if (filters.toDate) {
    params.push(filters.toDate);
    conditions.push(`al.created_at <= $${params.length}::date + INTERVAL '1 day'`);
  }

  return {
    clause: conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '',
    params,
  };
}

@Injectable()
export class AuditLogsRepository {
  constructor(private readonly db: DatabaseService) {}

  async list(
    filters: AuditLogListFilters,
    sort: AuditLogListSort,
  ): Promise<{ items: AuditLogListItem[]; total: number }> {
    const { clause, params } = buildWhereClause(filters);
    const orderDirection = sort.order === 'asc' ? 'ASC' : 'DESC';
    const offset = (sort.page - 1) * sort.limit;

    const listParams = [...params, sort.limit, offset];
    const limitPlaceholder = `$${listParams.length - 1}`;
    const offsetPlaceholder = `$${listParams.length}`;

    const [listResult, countResult] = await Promise.all([
      this.db.query<AuditLogListItem>(
        `SELECT al.id, al.user_id, actor.full_name AS user_name,
                al.target_user_id, target.full_name AS target_user_name,
                al.action, al.entity_type, al.entity_id,
                al.before_value, al.after_value, al.ip_address, al.created_at
         FROM audit_logs al
         LEFT JOIN users actor ON actor.id = al.user_id
         LEFT JOIN users target ON target.id = al.target_user_id
         ${clause}
         ORDER BY al.created_at ${orderDirection}
         LIMIT ${limitPlaceholder} OFFSET ${offsetPlaceholder}`,
        listParams,
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM audit_logs al ${clause}`, params),
    ]);

    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }
}
