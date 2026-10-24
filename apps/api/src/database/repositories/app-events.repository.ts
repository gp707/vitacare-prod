import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export type AppEventKind = 'screen' | 'tap';

export interface AppEventInput {
  kind: AppEventKind;
  flow: string;
  screen: string;
  action: string | null;
  /** When the tap/view actually happened on the device — events are sent in
   *  batches, so the server's own NOW() would smear a whole session onto the
   *  moment the batch arrived. Clamped by the service to a sane window. */
  occurredAt: Date;
}

export interface TopActionRow {
  kind: AppEventKind;
  flow: string;
  screen: string;
  action: string | null;
  count: number;
  unique_users: number;
}

/** Backing store for the admin Insights "most used buttons/screens" report —
 *  see migration 084's comment for the shape and retention. */
@Injectable()
export class AppEventsRepository {
  constructor(private readonly db: DatabaseService) {}

  async insertMany(events: AppEventInput[], userId: string | null, userRole: string | null): Promise<void> {
    if (events.length === 0) return;
    const values: unknown[] = [];
    const rows = events.map((event, i) => {
      const base = i * 7;
      values.push(userId, userRole, event.kind, event.flow, event.screen, event.action, event.occurredAt);
      return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}, $${base + 7})`;
    });
    await this.db.query(
      `INSERT INTO app_events (user_id, user_role, kind, flow, screen, action, created_at) VALUES ${rows.join(', ')}`,
      values,
    );
  }

  /** Most-used buttons (kind = 'tap') or screens (kind = 'screen') over the
   *  last [days], optionally narrowed to one [flow] (e.g. 'caregiver',
   *  'individual', 'organisation', 'auth'). Admin accounts never emit
   *  events, so no role filter is needed here. */
  async topActions(params: { kind: AppEventKind; days: number; flow?: string; limit: number }): Promise<TopActionRow[]> {
    const values: unknown[] = [params.kind, params.days];
    let flowClause = '';
    if (params.flow) {
      values.push(params.flow);
      flowClause = `AND flow = $${values.length}`;
    }
    values.push(params.limit);
    const result = await this.db.query<{
      kind: AppEventKind;
      flow: string;
      screen: string;
      action: string | null;
      count: string;
      unique_users: string;
    }>(
      `SELECT kind, flow, screen, action, COUNT(*) AS count, COUNT(DISTINCT user_id) AS unique_users
         FROM app_events
        WHERE kind = $1
          AND created_at >= NOW() - ($2 || ' days')::interval
          ${flowClause}
        GROUP BY kind, flow, screen, action
        ORDER BY COUNT(*) DESC, flow, screen, action
        LIMIT $${values.length}`,
      values,
    );
    return result.rows.map((row) => ({
      kind: row.kind,
      flow: row.flow,
      screen: row.screen,
      action: row.action,
      count: Number(row.count),
      unique_users: Number(row.unique_users),
    }));
  }

  async deleteOlderThan(cutoff: Date): Promise<number> {
    const result = await this.db.query('DELETE FROM app_events WHERE created_at < $1', [cutoff]);
    return result.rowCount ?? 0;
  }
}
