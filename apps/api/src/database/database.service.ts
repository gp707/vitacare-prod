import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryResult, QueryResultRow, types } from 'pg';

// pg's default DATE (OID 1082) parser returns a JS Date, which is
// timezone-aware and round-trips through toISOString() elsewhere (e.g. JSON
// responses) — shifting the calendar date by a day whenever the server's
// local timezone isn't UTC. DATE columns (jobs.start_date,
// caregiver_profiles.available_from) have no time component, so keep them
// as the raw 'YYYY-MM-DD' string Postgres sends instead.
types.setTypeParser(1082, (val) => val);

/** Minimal shape shared by DatabaseService and pg's PoolClient, for functions that
 *  optionally run inside a transaction (see DatabaseService.withTransaction). */
export interface QueryRunner {
  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly pool: Pool;

  constructor(configService: ConfigService) {
    this.pool = new Pool({
      connectionString: configService.getOrThrow<string>('DATABASE_URL'),
      ssl: { rejectUnauthorized: false },
    });
  }

  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params?: unknown[],
  ): Promise<QueryResult<T>> {
    return this.pool.query<T>(text, params);
  }

  async withTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}
