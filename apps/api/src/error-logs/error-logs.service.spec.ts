import { ErrorLogsService } from './error-logs.service';

describe('ErrorLogsService', () => {
  let errorLogsRepo: { list: jest.Mock; deleteOlderThan: jest.Mock };
  let requestStatsRepo: { listLastDays: jest.Mock };
  let service: ErrorLogsService;

  beforeEach(() => {
    errorLogsRepo = { list: jest.fn(), deleteOlderThan: jest.fn() };
    requestStatsRepo = { listLastDays: jest.fn() };
    service = new ErrorLogsService(errorLogsRepo as any, requestStatsRepo as any);
  });

  describe('list', () => {
    it('returns paginated data with a correct meta block', async () => {
      errorLogsRepo.list.mockResolvedValue({ items: [{ id: 'err-1' }], total: 45 });

      const result = await service.list({ page: 2, limit: 20 });

      expect(errorLogsRepo.list).toHaveBeenCalledWith({ page: 2, limit: 20 });
      expect(result).toEqual({
        data: [{ id: 'err-1' }],
        meta: { page: 2, limit: 20, total: 45, totalPages: 3 },
      });
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
