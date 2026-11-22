import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';

/** An alert stays under the bell until it is read or this many hours old, whichever is first. */
export const USER_NOTIFICATION_LIFETIME_HOURS = 48;

export interface UserNotificationRecord {
  id: string;
  title: string;
  body: string;
  route: string | null;
  created_at: Date;
}

@Injectable()
export class UserNotificationsRepository {
  constructor(private readonly db: DatabaseService) {}

  /** Stores one alert for every given account (duplicates ignored). */
  async insertForUsers(userIds: string[], title: string, body: string, route: string | null): Promise<void> {
    const unique = [...new Set(userIds)];
    if (unique.length === 0) return;
    await this.db.query(
      `INSERT INTO user_notifications (user_id, title, body, route)
       SELECT u, $2, $3, $4 FROM unnest($1::uuid[]) AS u`,
      [unique, title, body, route],
    );
  }

  /** Accounts that own any of these device tokens (a token belongs to one account at a time). */
  async userIdsForTokens(tokens: string[]): Promise<string[]> {
    if (tokens.length === 0) return [];
    const result = await this.db.query<{ user_id: string }>(
      `SELECT DISTINCT user_id FROM user_fcm_tokens WHERE token = ANY($1::text[])`,
      [tokens],
    );
    return result.rows.map((r) => r.user_id);
  }

  /** Unread and not yet expired, newest first. */
  async listActiveForUser(userId: string): Promise<UserNotificationRecord[]> {
    const result = await this.db.query<UserNotificationRecord>(
      `SELECT id, title, body, route, created_at
         FROM user_notifications
        WHERE user_id = $1 AND read_at IS NULL
          AND created_at > NOW() - make_interval(hours => $2)
        ORDER BY created_at DESC
        LIMIT 100`,
      [userId, USER_NOTIFICATION_LIFETIME_HOURS],
    );
    return result.rows;
  }

  /** Marks one of the caller's own alerts read. Returns whether anything changed. */
  async markRead(userId: string, id: string): Promise<boolean> {
    const result = await this.db.query(
      `UPDATE user_notifications SET read_at = NOW() WHERE id = $1 AND user_id = $2 AND read_at IS NULL`,
      [id, userId],
    );
    return (result.rowCount ?? 0) > 0;
  }

  /** Removes alerts past their lifetime and anything already read. */
  async purge(): Promise<number> {
    const result = await this.db.query(
      `DELETE FROM user_notifications
        WHERE read_at IS NOT NULL OR created_at < NOW() - make_interval(hours => $1)`,
      [USER_NOTIFICATION_LIFETIME_HOURS],
    );
    return result.rowCount ?? 0;
  }
}
