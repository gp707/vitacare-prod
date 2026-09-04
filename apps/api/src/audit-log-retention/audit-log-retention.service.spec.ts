import { AuditLogRetentionService } from './audit-log-retention.service';

describe('AuditLogRetentionService', () => {
  let service: AuditLogRetentionService;
  let retentionRepo: any;
  let auditLogsRepo: any;
  let auditService: any;

  const existingRow = {
    id: 1,
    retention_days: 180,
    updated_by: null,
    updated_at: new Date(),
  };

  beforeEach(() => {
    retentionRepo = { find: jest.fn(), findWithUpdater: jest.fn(), update: jest.fn() };
    auditLogsRepo = { deleteOlderThan: jest.fn() };
    auditService = { log: jest.fn() };
    service = new AuditLogRetentionService(retentionRepo, auditLogsRepo, auditService);
  });

  describe('adminGet', () => {
    it('returns the row joined with the updater name', async () => {
      const withUpdater = { ...existingRow, updated_by_name: 'Admin One' };
      retentionRepo.findWithUpdater.mockResolvedValue(withUpdater);
      const result = await service.adminGet();
      expect(result).toBe(withUpdater);
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs the before/after day counts', async () => {
      retentionRepo.find.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, retention_days: 90 };
      retentionRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminUpdate('admin-1', { retention_days: 90 }, '127.0.0.1');

      expect(result).toBe(updatedRow);
      expect(retentionRepo.update).toHaveBeenCalledWith(90, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'audit_log_retention_updated',
          entityType: 'audit_log_retention_settings',
          beforeValue: { retention_days: 180 },
          afterValue: { retention_days: 90 },
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });

  describe('purgeExpiredLogs', () => {
    it('deletes rows older than the configured retention window and audit-logs the sweep', async () => {
      retentionRepo.find.mockResolvedValue(existingRow);
      auditLogsRepo.deleteOlderThan.mockResolvedValue(42);

      await service.purgeExpiredLogs();

      expect(auditLogsRepo.deleteOlderThan).toHaveBeenCalledTimes(1);
      const cutoff: Date = auditLogsRepo.deleteOlderThan.mock.calls[0][0];
      const expectedCutoff = Date.now() - 180 * 24 * 60 * 60 * 1000;
      // Allow a small tolerance for time elapsed between computing the two.
      expect(Math.abs(cutoff.getTime() - expectedCutoff)).toBeLessThan(5000);

      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: null,
          action: 'audit_logs_purged',
          entityType: 'audit_logs',
          afterValue: expect.objectContaining({ deleted_count: 42, retention_days: 180 }),
          ipAddress: null,
        }),
      );
    });

    it('reads the retention window fresh on every run, not a value cached at startup', async () => {
      retentionRepo.find.mockResolvedValue({ ...existingRow, retention_days: 30 });
      auditLogsRepo.deleteOlderThan.mockResolvedValue(1);

      await service.purgeExpiredLogs();

      const cutoff: Date = auditLogsRepo.deleteOlderThan.mock.calls[0][0];
      const expectedCutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
      expect(Math.abs(cutoff.getTime() - expectedCutoff)).toBeLessThan(5000);
    });

    it('does not write an audit log entry when nothing was deleted', async () => {
      retentionRepo.find.mockResolvedValue(existingRow);
      auditLogsRepo.deleteOlderThan.mockResolvedValue(0);

      await service.purgeExpiredLogs();

      expect(auditService.log).not.toHaveBeenCalled();
    });
  });
});
