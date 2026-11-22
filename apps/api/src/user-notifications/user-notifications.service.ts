import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { AppException } from '../common/exceptions/app.exception';
import { UserNotificationsRepository } from '../database/repositories/user-notifications.repository';

/** The alerts kept under a person's bell: unread and under 2 days old. */
@Injectable()
export class UserNotificationsService {
  private readonly logger = new Logger(UserNotificationsService.name);

  constructor(private readonly repo: UserNotificationsRepository) {}

  async list(userId: string) {
    const rows = await this.repo.listActiveForUser(userId);
    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      body: r.body,
      route: r.route,
      created_at: r.created_at,
    }));
  }

  /** Reading an alert takes it off the bell for good. Someone else's (or an already read) alert is GEN_002. */
  async markRead(userId: string, id: string) {
    const changed = await this.repo.markRead(userId, id);
    if (!changed) throw new AppException('GEN_002');
    return { message: 'Marked as read' };
  }

  /** Clears read and expired alerts every night (the API already hides them; this just keeps the table small). */
  @Cron('45 3 * * *', { timeZone: 'Asia/Kolkata' })
  async purge(): Promise<void> {
    try {
      const removed = await this.repo.purge();
      if (removed > 0) this.logger.log(`Purged ${removed} read or expired bell alerts`);
    } catch (error) {
      this.logger.error('Failed to purge bell alerts', error);
    }
  }
}
