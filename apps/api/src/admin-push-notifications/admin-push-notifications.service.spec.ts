import { AdminPushNotificationsService } from './admin-push-notifications.service';

describe('AdminPushNotificationsService', () => {
  let service: AdminPushNotificationsService;
  let repo: any;
  let usersRepo: any;
  let fcmService: any;
  let auditService: any;

  const notification = {
    id: 'notif-1',
    created_by: 'admin-1',
    title: 'Heads up',
    body: 'Please update your documents',
    scheduled_at: new Date('2026-01-01T00:00:00Z'),
    sent_at: null,
    status: 'pending' as const,
    recipient_count: 2,
    created_at: new Date('2026-01-01T00:00:00Z'),
  };

  beforeEach(() => {
    repo = {
      create: jest.fn().mockResolvedValue(notification),
      findDuePending: jest.fn().mockResolvedValue([]),
      getRecipientUserIds: jest.fn().mockResolvedValue(['user-1', 'user-2']),
      markSent: jest.fn(),
      markFailed: jest.fn(),
      findById: jest.fn(),
      cancel: jest.fn(),
      list: jest.fn(),
    };
    usersRepo = { listFcmTokensByUserIds: jest.fn().mockResolvedValue(['token-1', 'token-2']) };
    fcmService = { sendToTokens: jest.fn() };
    auditService = { log: jest.fn() };
    service = new AdminPushNotificationsService(repo, usersRepo, fcmService, auditService);
  });

  describe('create', () => {
    it('sends immediately and returns status "sent" when scheduled_at is omitted', async () => {
      const result = await service.create(
        'admin-1',
        { title: 'Heads up', body: 'Please update your documents', recipient_user_ids: ['user-1', 'user-2'] } as any,
        '127.0.0.1',
      );

      expect(repo.create).toHaveBeenCalledWith(
        'admin-1',
        'Heads up',
        'Please update your documents',
        expect.any(Date),
        ['user-1', 'user-2'],
      );
      expect(usersRepo.listFcmTokensByUserIds).toHaveBeenCalledWith(['user-1', 'user-2']);
      expect(fcmService.sendToTokens).toHaveBeenCalledWith(
        ['token-1', 'token-2'],
        'Heads up',
        'Please update your documents',
      );
      expect(repo.markSent).toHaveBeenCalledWith('notif-1');
      expect(result).toEqual({ ...notification, status: 'sent' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'push_notification_created',
          entityType: 'admin_push_notifications',
          entityId: 'notif-1',
          afterValue: expect.objectContaining({ title: 'Heads up', recipient_count: 2 }),
        }),
      );
    });

    it('sends immediately when scheduled_at is in the past', async () => {
      await service.create(
        'admin-1',
        {
          title: 'Heads up',
          body: 'Body',
          recipient_user_ids: ['user-1'],
          scheduled_at: '2020-01-01T00:00:00Z',
        } as any,
        null,
      );
      expect(fcmService.sendToTokens).toHaveBeenCalled();
      expect(repo.markSent).toHaveBeenCalled();
    });

    it('leaves the notification pending (no send) when scheduled_at is in the future', async () => {
      const futureDate = new Date(Date.now() + 60 * 60 * 1000).toISOString();
      const result = await service.create(
        'admin-1',
        { title: 'Heads up', body: 'Body', recipient_user_ids: ['user-1'], scheduled_at: futureDate } as any,
        null,
      );
      expect(fcmService.sendToTokens).not.toHaveBeenCalled();
      expect(repo.markSent).not.toHaveBeenCalled();
      expect(result).toEqual(notification);
    });

    it('marks the notification failed when sending throws, without throwing itself, and reports status "failed"', async () => {
      fcmService.sendToTokens.mockRejectedValue(new Error('FCM down'));
      const result = await service.create(
        'admin-1',
        { title: 'Heads up', body: 'Body', recipient_user_ids: ['user-1'] } as any,
        null,
      );
      expect(repo.markFailed).toHaveBeenCalledWith('notif-1');
      expect(repo.markSent).not.toHaveBeenCalled();
      expect(result).toEqual({ ...notification, status: 'failed' });
    });
  });

  describe('processDueNotifications', () => {
    it('sends every due pending notification', async () => {
      repo.findDuePending.mockResolvedValue([notification, { ...notification, id: 'notif-2' }]);
      await service.processDueNotifications();
      expect(repo.markSent).toHaveBeenCalledWith('notif-1');
      expect(repo.markSent).toHaveBeenCalledWith('notif-2');
    });

    it('does nothing when nothing is due', async () => {
      repo.findDuePending.mockResolvedValue([]);
      await service.processDueNotifications();
      expect(fcmService.sendToTokens).not.toHaveBeenCalled();
    });
  });

  describe('list', () => {
    it('paginates and shapes meta correctly', async () => {
      repo.list.mockResolvedValue({ items: [notification], total: 25 });
      const result = await service.list({ page: 2, limit: 10 } as any);
      expect(repo.list).toHaveBeenCalledWith({ page: 2, limit: 10 });
      expect(result.data).toEqual([notification]);
      expect(result.meta).toEqual({ page: 2, limit: 10, total: 25, totalPages: 3 });
    });
  });

  describe('cancel', () => {
    it('throws GEN_002 when the notification does not exist', async () => {
      repo.findById.mockResolvedValue(null);
      await expect(service.cancel('notif-1', 'admin-1', null)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws PUSH_001 when the notification is not pending (already sent/failed/cancelled)', async () => {
      repo.findById.mockResolvedValue({ ...notification, status: 'sent' });
      repo.cancel.mockResolvedValue(null);
      await expect(service.cancel('notif-1', 'admin-1', null)).rejects.toMatchObject({ code: 'PUSH_001' });
    });

    it('cancels a pending notification and audit-logs it', async () => {
      repo.findById.mockResolvedValue(notification);
      repo.cancel.mockResolvedValue({ ...notification, status: 'cancelled' });
      const result = await service.cancel('notif-1', 'admin-1', '127.0.0.1');
      expect(result).toEqual({ message: 'Notification cancelled' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'push_notification_cancelled',
          entityType: 'admin_push_notifications',
          entityId: 'notif-1',
        }),
      );
    });
  });
});
