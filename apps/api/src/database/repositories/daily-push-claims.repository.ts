import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

/** At-most-once-per-day guard for scheduled broadcast pushes (migration 090). */
@Injectable()
export class DailyPushClaimsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Claims [kind] for the IST calendar day [sentOn] (YYYY-MM-DD). Returns
   *  true only for the one caller that got it; every other instance or retry
   *  that day gets false and must not send. */
  async claim(kind: string, sentOn: string, detail: Record<string, unknown> = {}): Promise<boolean> {
    const result = await this.db.query(
      `INSERT INTO daily_push_claims (kind, sent_on, detail) VALUES ($1, $2::date, $3::jsonb)
       ON CONFLICT (kind, sent_on) DO NOTHING
       RETURNING kind`,
      [kind, sentOn, JSON.stringify(detail)],
    );
    return (result.rowCount ?? 0) > 0;
  }
}
