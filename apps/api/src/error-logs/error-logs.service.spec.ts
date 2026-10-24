import { ErrorLogsService } from './error-logs.service';

describe('ErrorLogsService', () => {
  let errorLogsRepo: {
    list: jest.Mock;
    deleteOlderThan: jest.Mock;
    listAffectedUsers: jest.Mock;
    findById: jest.Mock;
    resolve: jest.Mock;
    resolveAllForUser: jest.Mock;
  };
  let requestStatsRepo: { listLastDays: jest.Mock };
  let auditService: { log: jest.Mock };
  let service: ErrorLogsService;

  beforeEach(() => {
    errorLogsRepo = {
      list: jest.fn(),
      deleteOlderThan: jest.fn(),
      listAffectedUsers: jest.fn(),
      findById: jest.fn(),
      resolve: jest.fn(),
      resolveAllForUser: jest.fn(),
    };
    requestStatsRepo = { listLastDays: jest.fn() };
    auditService = { log: jest.fn().mockResolvedValue(undefined) };
    service = new ErrorLogsService(errorLogsRepo as any, requestStatsRepo as any, auditService as any);
  });

  describe('list', () => {
    it('returns paginated data with a correct meta block', async () => {
      errorLogsRepo.list.mockResolvedValue({ items: [{ id: 'err-1' }], total: 45 });

      const result = await service.list({ page: 2, limit: 20, status: 'all' });

      expect(errorLogsRepo.list).toHaveBeenCalledWith(
        { page: 2, limit: 20 },
        { status: 'all', userId: undefined, search: undefined },
      );
      expect(result).toEqual({
        data: [{ id: 'err-1' }],
        meta: { page: 2, limit: 20, total: 45, totalPages: 3 },
      });
    });

    it('passes the status, user and search filters through to the repository', async () => {
      errorLogsRepo.list.mockResolvedValue({ items: [], total: 0 });
      await service.list({ page: 1, limit: 20, status: 'open', user_id: 'u-1', search: '/auth/login' });
      expect(errorLogsRepo.list).toHaveBeenCalledWith(
        { page: 1, limit: 20 },
        { status: 'open', userId: 'u-1', search: '/auth/login' },
      );
    });
  });

  describe('listAffectedUsers', () => {
    it('returns the people hit by errors with a pagination meta, defaulting to open errors', async () => {
      errorLogsRepo.listAffectedUsers.mockResolvedValue({ items: [{ user_id: 'u1', phone: '+919876543210' }], total: 31 });
      const result = await service.listAffectedUsers({ page: 1, limit: 25, status: 'open' });
      expect(errorLogsRepo.listAffectedUsers).toHaveBeenCalledWith({ page: 1, limit: 25 }, 'open');
      expect(result.meta).toEqual({ page: 1, limit: 25, total: 31, totalPages: 2 });
      expect(result.data).toEqual([{ user_id: 'u1', phone: '+919876543210' }]);
    });
  });

  describe('resolve', () => {
    it('resolves an open error and audit-logs it against the affected person', async () => {
      errorLogsRepo.findById.mockResolvedValue({ id: 'e1', user_id: 'u1', status: 'open' });
      errorLogsRepo.resolve.mockResolvedValue(true);

      const result = await service.resolve('e1', 'admin-1', 'Called, re-registered', '1.2.3.4');

      expect(errorLogsRepo.resolve).toHaveBeenCalledWith('e1', 'admin-1', 'Called, re-registered');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'u1',
          action: 'error_log_resolved',
          entityType: 'error_logs',
          entityId: 'e1',
          afterValue: { note: 'Called, re-registered' },
        }),
      );
      expect(result.message).toBe('Error marked resolved');
    });

    it('is idempotent: resolving an already-resolved error is a no-op with no second audit entry', async () => {
      errorLogsRepo.findById.mockResolvedValue({ id: 'e1', user_id: 'u1', status: 'resolved' });
      errorLogsRepo.resolve.mockResolvedValue(false);

      const result = await service.resolve('e1', 'admin-1', undefined, null);

      expect(auditService.log).not.toHaveBeenCalled();
      expect(result.message).toBe('Error was already resolved');
    });

    it('404s (GEN_002) for an error that does not exist', async () => {
      errorLogsRepo.findById.mockResolvedValue(null);
      await expect(service.resolve('nope', 'admin-1', undefined, null)).rejects.toMatchObject({ code: 'GEN_002' });
      expect(errorLogsRepo.resolve).not.toHaveBeenCalled();
    });

    it('audits an anonymous error (no affected user) without a target', async () => {
      errorLogsRepo.findById.mockResolvedValue({ id: 'e2', user_id: null, status: 'open' });
      errorLogsRepo.resolve.mockResolvedValue(true);
      await service.resolve('e2', 'admin-1', undefined, null);
      expect(auditService.log).toHaveBeenCalledWith(expect.objectContaining({ targetUserId: undefined }));
    });
  });

  describe('resolveAllForUser', () => {
    it('resolves every open error for a person and audit-logs the count once', async () => {
      errorLogsRepo.resolveAllForUser.mockResolvedValue(3);
      const result = await service.resolveAllForUser('u1', 'admin-1', 'Called them', null);
      expect(errorLogsRepo.resolveAllForUser).toHaveBeenCalledWith('u1', 'admin-1', 'Called them');
      expect(result).toEqual({ resolved_count: 3 });
      expect(auditService.log).toHaveBeenCalledTimes(1);
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ targetUserId: 'u1', afterValue: { note: 'Called them', resolved_count: 3 } }),
      );
    });

    it('does not audit when there was nothing open to resolve', async () => {
      errorLogsRepo.resolveAllForUser.mockResolvedValue(0);
      expect(await service.resolveAllForUser('u1', 'admin-1', undefined, null)).toEqual({ resolved_count: 0 });
      expect(auditService.log).not.toHaveBeenCalled();
    });
  });

  describe('getStats', () => {
    it('delegates to RequestStatsRepository.listLastDays', async () => {
      const rows = [{ date: '2026-10-22', total_requests: 10, total_errors: 1 }];
      requestStatsRepo.listLastDays.mockResolvedValue(rows);

      const result = await service.getStats(7);

      expect(requestStatsRepo.listLastDays).toHaveBeenCalledWith(7);
      expect(result).toBe(rows);
    });
  });

  describe('purgeExpiredLogs', () => {
    it('deletes rows older than 7 days', async () => {
      errorLogsRepo.deleteOlderThan.mockResolvedValue(12);

      await service.purgeExpiredLogs();

      expect(errorLogsRepo.deleteOlderThan).toHaveBeenCalledTimes(1);
      const cutoff = errorLogsRepo.deleteOlderThan.mock.calls[0][0] as Date;
      const expectedCutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
      // Allow a small tolerance for the time elapsed between computing
      // expectedCutoff here and inside the service call.
      expect(Math.abs(cutoff.getTime() - expectedCutoff)).toBeLessThan(5000);
    });

    it('does nothing further when nothing was deleted', async () => {
      errorLogsRepo.deleteOlderThan.mockResolvedValue(0);
      await expect(service.purgeExpiredLogs()).resolves.toBeUndefined();
    });
  });
});
