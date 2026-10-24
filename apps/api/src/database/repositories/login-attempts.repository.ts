import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface CreateLoginAttemptInput {
  phone: string;
  userId: string | null;
  userRole: string | null;
  app: string;
  method: 'code' | 'otp';
  reason: string;
  ipAddress: string | null;
  userAgent: string | null;
}

/** Backing store for the admin Insights "Login problems" report — see
 *  migration 086's comment for what is (and deliberately is not) recorded.
 *  Read queries live in InsightsRepository alongside the other reports. */
@Injectable()
export class LoginAttemptsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(input: CreateLoginAttemptInput): Promise<void> {
    await this.db.query(
      `INSERT INTO login_attempts (phone, user_id, user_role, app, method, reason, ip_address, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        input.phone,
        input.userId,
        input.userRole,
        input.app,
        input.method,
        input.reason,
        input.ipAddress,
        input.userAgent,
      ],
    );
  }

  async deleteOlderThan(cutoff: Date): Promise<number> {
    const result = await this.db.query('DELETE FROM login_attempts WHERE created_at < $1', [cutoff]);
    return result.rowCount ?? 0;
  }
}
