import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface DailyRequestStats {
  date: string;
  total_requests: number;
  total_errors: number;
}

/** One row per calendar day (UTC, Postgres CURRENT_DATE) — see migration
 *  083's comment. Written by a request-counting middleware on every
 *  response, not per-request logging, so this stays a single cheap UPSERT
 *  per request rather than a row-per-request table. */
@Injectable()
export class RequestStatsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Fire-and-forget from the middleware — never awaited on the request's
   *  own response path. [isError] is whether this response was a 5xx. */
  async increment(isError: boolean): Promise<void> {
    await this.db.query(
      `INSERT INTO request_stats (date, total_requests, total_errors)
       VALUES (CURRENT_DATE, 1, $1)
       ON CONFLICT (date) DO UPDATE SET
         total_requests = request_stats.total_requests + 1,
         total_errors = request_stats.total_errors + EXCLUDED.total_errors`,
      [isError ? 1 : 0],
    );
  }

  /** Last [days] calendar days including today, oldest first — a day with
   *  no traffic simply has no row, not a zero-filled gap (admin-web fills
   *  gaps for display if it wants an unbroken chart). */
  async listLastDays(days: number): Promise<DailyRequestStats[]> {
    // `date` comes back as a plain 'YYYY-MM-DD' string, not a JS Date — see
    // DatabaseService's DATE (OID 1082) type-parser override.
    const result = await this.db.query<{ date: string; total_requests: string; total_errors: string }>(
      `SELECT * FROM request_stats WHERE date >= CURRENT_DATE - ($1 || ' days')::interval ORDER BY date ASC`,
      [days - 1],
    );
    return result.rows.map((row) => ({
      date: row.date,
      total_requests: Number(row.total_requests),
      total_errors: Number(row.total_errors),
    }));
  }
}
