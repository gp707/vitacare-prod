import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

export interface OtpVerificationRecord {
  id: string;
  phone: string;
  app: string;
  purpose: string;
  otp_hash: string;
  expires_at: Date;
  attempts: number;
  max_attempts: number;
  consumed_at: Date | null;
  created_at: Date;
}

@Injectable()
export class OtpVerificationsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(
    phone: string,
    app: string,
    purpose: string,
    otpHash: string,
    expiresAt: Date,
  ): Promise<OtpVerificationRecord> {
    const result = await this.db.query<OtpVerificationRecord>(
      `INSERT INTO otp_verifications (phone, app, purpose, otp_hash, expires_at)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [phone, app, purpose, otpHash, expiresAt],
    );
    return result.rows[0];
  }

  /** Most recent still-usable row for this phone+app+purpose — not yet
   *  consumed, not yet expired, and under its attempt limit. Older rows
   *  for the same phone+app+purpose are simply ignored once a newer one
   *  exists (a fresh "send" always supersedes an earlier unconsumed one). */
  async findLatestActive(phone: string, app: string, purpose: string): Promise<OtpVerificationRecord | null> {
    const result = await this.db.query<OtpVerificationRecord>(
      `SELECT * FROM otp_verifications
       WHERE phone = $1 AND app = $2 AND purpose = $3
         AND consumed_at IS NULL AND expires_at > NOW()
       ORDER BY created_at DESC
       LIMIT 1`,
      [phone, app, purpose],
    );
    return result.rows[0] ?? null;
  }

  async incrementAttempts(id: string): Promise<OtpVerificationRecord> {
    const result = await this.db.query<OtpVerificationRecord>(
      `UPDATE otp_verifications SET attempts = attempts + 1 WHERE id = $1 RETURNING *`,
      [id],
    );
    return result.rows[0];
  }

  async markConsumed(id: string): Promise<void> {
    await this.db.query('UPDATE otp_verifications SET consumed_at = NOW() WHERE id = $1', [id]);
  }

  /** Drives both the 30s resend cooldown (sinceMinutes small) and the
   *  rolling 5-per-60min cap (sinceMinutes larger) — same query, different
   *  window, so both throttles share this one method. */
  async countRecentSends(phone: string, app: string, purpose: string, sinceMinutes: number): Promise<number> {
    const result = await this.db.query<{ count: string }>(
      `SELECT COUNT(*)::int AS count FROM otp_verifications
       WHERE phone = $1 AND app = $2 AND purpose = $3
         AND created_at > NOW() - ($4 * INTERVAL '1 minute')`,
      [phone, app, purpose, sinceMinutes],
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  /** Cooldown-specific: seconds since the single most recent send, or null
   *  if none exists yet. Used to compute a precise "try again in Ns"
   *  rather than just a boolean. */
  async secondsSinceLastSend(phone: string, app: string, purpose: string): Promise<number | null> {
    const result = await this.db.query<{ seconds: number | null }>(
      `SELECT EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))::int AS seconds
       FROM otp_verifications WHERE phone = $1 AND app = $2 AND purpose = $3`,
      [phone, app, purpose],
    );
    return result.rows[0]?.seconds ?? null;
  }
}
