import { JobSettingsService } from './job-settings.service';

describe('JobSettingsService', () => {
  let service: JobSettingsService;
  let jobSettingsRepo: any;
  let auditService: any;

  const existingRow = {
    id: 1,
    apply_by_window_days: 3,
    updated_by: null,
    updated_at: new Date(),
  };

  beforeEach(() => {
    jobSettingsRepo = { find: jest.fn(), findWithUpdater: jest.fn(), update: jest.fn() };
    auditService = { log: jest.fn() };
    service = new JobSettingsService(jobSettingsRepo, auditService);
  });

  describe('get', () => {
    it('returns the singleton row from the repository', async () => {
      jobSettingsRepo.find.mockResolvedValue(existingRow);
      const result = await service.get();
      expect(result).toBe(existingRow);
    });
  });

  describe('adminGet', () => {
    it('returns the row joined with the updater name', async () => {
      const withUpdater = { ...existingRow, updated_by_name: 'Admin One' };
      jobSettingsRepo.findWithUpdater.mockResolvedValue(withUpdater);
      const result = await service.adminGet();
      expect(result).toBe(withUpdater);
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs the before/after day counts', async () => {
      jobSettingsRepo.find.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, apply_by_window_days: 5 };
      jobSettingsRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminUpdate('admin-1', { apply_by_window_days: 5 }, '127.0.0.1');

      expect(result).toBe(updatedRow);
      expect(jobSettingsRepo.update).toHaveBeenCalledWith(5, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'job_settings_updated',
          entityType: 'job_settings',
          beforeValue: { apply_by_window_days: 3 },
          afterValue: { apply_by_window_days: 5 },
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });
});
