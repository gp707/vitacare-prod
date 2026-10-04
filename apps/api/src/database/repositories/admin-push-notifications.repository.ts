import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database.service';
import { ListPage } from './jobs.repository';

export interface AdminPushNotificationRecord {
  id: string;
  created_by: string;
  title: string;
  body: string;
  scheduled_at: Date;
  sent_at: Date | null;
  status: 'pending' | 'sent' | 'failed' | 'cancelled';
  recipient_count: number;
  created_at: Date;
}

export interface AdminPushNotificationWithCreator extends AdminPushNotificationRecord {
  created_by_name: string;
}

/** Composed message + schedule lives here; who it goes to lives in
 *  admin_push_notification_recipients (plain user_id — role-agnostic,
 *  since one notification can target a mix of caregiver/individual/
 *  organisation accounts at once). */
@Injectable()
export class AdminPushNotificationsRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(
    createdBy: string,
    title: string,
    body: string,
    scheduledAt: Date,
    recipientUserIds: string[],
  ): Promise<AdminPushNotificationRecord> {
    return this.db.withTransaction(async (client) => {
      const result = await client.query<AdminPushNotificationRecord>(
        `INSERT INTO admin_push_notifications (created_by, title, body, scheduled_at, recipient_count)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [createdBy, title, body, scheduledAt, recipientUserIds.length],
      );
      const notification = result.rows[0];

      const values: string[] = [];
      const params: unknown[] = [notification.id];
      recipientUserIds.forEach((userId, i) => {
        params.push(userId);
        values.push(`($1, $${params.length})`);
      });
      await client.query(
        `INSERT INTO admin_push_notification_recipients (notification_id, user_id) VALUES ${values.join(', ')}`,
        params,
      );

      return notification;
    });
  }

  /** Every pending notification whose scheduled_at has arrived — picked up
   *  by AdminPushNotificationsService's minute-poll cron. */
  async findDuePending(now: Date): Promise<AdminPushNotificationRecord[]> {
    const result = await this.db.query<AdminPushNotificationRecord>(
      `SELECT * FROM admin_push_notifications WHERE status = 'pending' AND scheduled_at <= $1`,
      [now],
    );
    return result.rows;
  }

  async getRecipientUserIds(notificationId: string): Promise<string[]> {
    const result = await this.db.query<{ user_id: string }>(
      `SELECT user_id FROM admin_push_notification_recipients WHERE notification_id = $1`,
      [notificationId],
    );
    return result.rows.map((row) => row.user_id);
  }

  async markSent(id: string): Promise<void> {
    await this.db.query(`UPDATE admin_push_notifications SET status = 'sent', sent_at = NOW() WHERE id = $1`, [id]);
  }

  async markFailed(id: string): Promise<void> {
    await this.db.query(`UPDATE admin_push_notifications SET status = 'failed' WHERE id = $1`, [id]);
  }

  async findById(id: string): Promise<AdminPushNotificationRecord | null> {
    const result = await this.db.query<AdminPushNotificationRecord>(
      `SELECT * FROM admin_push_notifications WHERE id = $1`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  /** Only a still-pending (not yet sent/failed), future-scheduled
   *  notification can be cancelled — returns null (not an exception) when
   *  that's not the case, so the service can turn it into the right error
   *  code. */
  async cancel(id: string): Promise<AdminPushNotificationRecord | null> {
    const result = await this.db.query<AdminPushNotificationRecord>(
      `UPDATE admin_push_notifications SET status = 'cancelled' WHERE id = $1 AND status = 'pending' RETURNING *`,
      [id],
    );
    return result.rows[0] ?? null;
  }

  async list(page: ListPage): Promise<{ items: AdminPushNotificationWithCreator[]; total: number }> {
    const offset = (page.page - 1) * page.limit;
    const [listResult, countResult] = await Promise.all([
      this.db.query<AdminPushNotificationWithCreator>(
        `SELECT n.*, u.full_name AS created_by_name
         FROM admin_push_notifications n
         JOIN users u ON u.id = n.created_by
         ORDER BY n.created_at DESC
         LIMIT $1 OFFSET $2`,
        [page.limit, offset],
      ),
      this.db.query<{ count: string }>(`SELECT COUNT(*) FROM admin_push_notifications`),
    ]);
    return { items: listResult.rows, total: Number(countResult.rows[0].count) };
  }
}
