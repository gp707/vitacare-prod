import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import {
  AdminPushNotificationRecord,
  AdminPushNotificationsRepository,
} from '../database/repositories/admin-push-notifications.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { FcmService } from '../fcm/fcm.service';
import { CreatePushNotificationDto } from './dto/create-push-notification.dto';
import { ListPushNotificationsQueryDto } from './dto/list-push-notifications-query.dto';

@Injectable()
export class AdminPushNotificationsService {
  private readonly logger = new Logger(AdminPushNotificationsService.name);

  constructor(
    private readonly repo: AdminPushNotificationsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly fcmService: FcmService,
    private readonly auditService: AuditService,
  ) {}

  /** [dto.scheduled_at] omitted or already in the past sends immediately,
   *  in the same request — otherwise it's queued for the minute-poll cron
   *  below. Recipients are a plain array of user ids (role-agnostic — the
   *  admin-web selection cart can mix caregiver/individual/organisation
   *  accounts in one notification), resolved against the already-selected
   *  users at send time, never re-derived from a saved filter. */
  async create(adminId: string, dto: CreatePushNotificationDto, ipAddress: string | null) {
    const scheduledAt = dto.scheduled_at ? new Date(dto.scheduled_at) : new Date();
    const notification = await this.repo.create(
      adminId,
      dto.title,
      dto.body,
      scheduledAt,
      dto.recipient_user_ids,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.PUSH_NOTIFICATION_CREATED,
      entityType: 'admin_push_notifications',
      entityId: notification.id,
      afterValue: { title: dto.title, recipient_count: dto.recipient_user_ids.length, scheduled_at: scheduledAt },
      ipAddress,
    });

    if (scheduledAt <= new Date()) {
      const sent = await this.send(notification);
      return { ...notification, status: sent ? ('sent' as const) : ('failed' as const) };
    }

    return notification;
  }

  async list(query: ListPushNotificationsQueryDto) {
    const { items, total } = await this.repo.list({ page: query.page, limit: query.limit });
    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };
    return { data: items, meta };
  }

  /** Only a still-pending, future-scheduled notification can be
   *  cancelled — GEN_002 if it doesn't exist, PUSH_001 if it already sent/
   *  failed/was cancelled. */
  async cancel(id: string, adminId: string, ipAddress: string | null) {
    const existing = await this.repo.findById(id);
    if (!existing) throw new AppException('GEN_002');

    const cancelled = await this.repo.cancel(id);
    if (!cancelled) throw new AppException('PUSH_001');

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.PUSH_NOTIFICATION_CANCELLED,
      entityType: 'admin_push_notifications',
      entityId: id,
      ipAddress,
    });

    return { message: 'Notification cancelled' };
  }

  /** Every minute, send whatever just became due — low enough volume
   *  (admin-composed, not a per-user trigger) that a simple poll is plenty;
   *  no overlap guard needed since each row's own status='pending' check
   *  inside send() makes a double-pick-up a no-op on the second run. */
  @Cron('* * * * *')
  async processDueNotifications(): Promise<void> {
    const due = await this.repo.findDuePending(new Date());
    for (const notification of due) {
      await this.send(notification);
    }
  }

  /** Returns whether it actually sent — create() uses this to report the
   *  right status back to the admin for an immediate send, rather than
   *  optimistically claiming "sent" regardless of outcome. */
  private async send(notification: AdminPushNotificationRecord): Promise<boolean> {
    try {
      const recipientUserIds = await this.repo.getRecipientUserIds(notification.id);
      const tokens = await this.usersRepo.listFcmTokensByUserIds(recipientUserIds);
      await this.fcmService.sendToTokens(tokens, notification.title, notification.body);
      await this.repo.markSent(notification.id);
      return true;
    } catch (error) {
      this.logger.error(`Failed to send push notification ${notification.id}`, error);
      await this.repo.markFailed(notification.id);
      return false;
    }
  }
}
