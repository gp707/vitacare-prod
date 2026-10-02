import { AppConfigService } from './app-config.service';

describe('AppConfigService', () => {
  let service: AppConfigService;
  let appMinVersionsRepo: any;
  let appMaintenanceRepo: any;
  let auditService: any;

  const androidRow = {
    platform: 'android',
    min_version: '1.2.0',
    store_url: 'https://play.google.com/store/apps/details?id=in.vitacasahealth.justheal',
    update_message: 'Please update to continue using JustHeal.',
    updated_by: 'admin-1',
    updated_at: new Date(),
  };

  const maintenanceRow = {
    enabled: false,
    message: null,
    updated_by: null,
    updated_at: new Date(),
  };

  beforeEach(() => {
    appMinVersionsRepo = {
      findByPlatform: jest.fn(),
      findAll: jest.fn(),
      update: jest.fn(),
    };
    appMaintenanceRepo = {
      find: jest.fn(),
      findWithUpdater: jest.fn(),
      update: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new AppConfigService(appMinVersionsRepo, appMaintenanceRepo, auditService);
  });

  describe('checkVersion', () => {
    it('throws GEN_002 for an unrecognized platform', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(null);
      await expect(service.checkVersion('windows' as any, '1.0.0')).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('requires an update when the installed version is below min_version', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('android' as any, '1.1.0');
      expect(result).toEqual({
        update_required: true,
        min_version: '1.2.0',
        store_url: androidRow.store_url,
        update_message: androidRow.update_message,
      });
      expect(appMinVersionsRepo.findByPlatform).toHaveBeenCalledWith('android');
    });

    it('does not require an update when the installed version equals min_version', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('android' as any, '1.2.0');
      expect(result.update_required).toBe(false);
      expect(result.store_url).toBeNull();
      expect(result.update_message).toBeNull();
    });

    it('does not require an update when the installed version is above min_version', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('android' as any, '2.0.0');
      expect(result.update_required).toBe(false);
    });

    it('compares minor/patch correctly, not lexicographically (2.10.0 beats 2.9.0)', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue({ ...androidRow, min_version: '2.10.0' });
      const result = await service.checkVersion('android' as any, '2.9.0');
      expect(result.update_required).toBe(true);
    });

    it('treats a malformed current version as 0.0.0 rather than throwing', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('android' as any, 'not-a-version');
      expect(result.update_required).toBe(true);
    });
  });

  describe('adminList', () => {
    it('returns every platform row from the repository', async () => {
      appMinVersionsRepo.findAll.mockResolvedValue([androidRow]);
      const result = await service.adminList();
      expect(result).toEqual([androidRow]);
    });
  });

  describe('adminUpdate', () => {
    it('throws GEN_002 for an unrecognized platform', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(null);
      await expect(service.adminUpdate('admin-1', 'windows', { min_version: '1.0.0' }, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(appMinVersionsRepo.update).not.toHaveBeenCalled();
    });

    it('updates the row and audit-logs before/after values', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      const updatedRow = { ...androidRow, min_version: '1.3.0' };
      appMinVersionsRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminUpdate(
        'admin-1',
        'android',
        { min_version: '1.3.0', store_url: 'https://play.google.com/x' },
        '127.0.0.1',
      );

      expect(result).toBe(updatedRow);
      expect(appMinVersionsRepo.update).toHaveBeenCalledWith(
        'android',
        { min_version: '1.3.0', store_url: 'https://play.google.com/x' },
        'admin-1',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'app_version_updated',
          entityType: 'app_min_versions',
          beforeValue: { platform: 'android', min_version: '1.2.0', store_url: androidRow.store_url },
          afterValue: { platform: 'android', min_version: '1.3.0', store_url: 'https://play.google.com/x' },
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });

  describe('checkMaintenance', () => {
    it('throws GEN_002 when the singleton row is somehow missing', async () => {
      appMaintenanceRepo.find.mockResolvedValue(null);
      await expect(service.checkMaintenance()).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns enabled: false and no message when maintenance is off', async () => {
      appMaintenanceRepo.find.mockResolvedValue(maintenanceRow);
      const result = await service.checkMaintenance();
      expect(result).toEqual({ enabled: false, message: null });
    });

    it('returns the message when maintenance is on', async () => {
      appMaintenanceRepo.find.mockResolvedValue({
        ...maintenanceRow,
        enabled: true,
        message: 'App is in maintenance mode, it will be available after 10am IST.',
      });
      const result = await service.checkMaintenance();
      expect(result).toEqual({
        enabled: true,
        message: 'App is in maintenance mode, it will be available after 10am IST.',
      });
    });

    it('suppresses a stale message once maintenance is turned back off', async () => {
      appMaintenanceRepo.find.mockResolvedValue({
        ...maintenanceRow,
        enabled: false,
        message: 'Old message left over from a previous maintenance window.',
      });
      const result = await service.checkMaintenance();
      expect(result.message).toBeNull();
    });
  });

  describe('adminMaintenance', () => {
    it('returns the singleton row from the repository', async () => {
      appMaintenanceRepo.findWithUpdater.mockResolvedValue(maintenanceRow);
      const result = await service.adminMaintenance();
      expect(result).toEqual(maintenanceRow);
    });
  });

  describe('adminMaintenanceUpdate', () => {
    it('throws GEN_002 when the singleton row is somehow missing', async () => {
      appMaintenanceRepo.find.mockResolvedValue(null);
      await expect(service.adminMaintenanceUpdate('admin-1', { enabled: true }, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(appMaintenanceRepo.update).not.toHaveBeenCalled();
    });

    it('updates the row and audit-logs before/after values', async () => {
      appMaintenanceRepo.find.mockResolvedValue(maintenanceRow);
      const updatedRow = {
        ...maintenanceRow,
        enabled: true,
        message: 'App is in maintenance mode, it will be available after 10am IST.',
      };
      appMaintenanceRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminMaintenanceUpdate(
        'admin-1',
        { enabled: true, message: 'App is in maintenance mode, it will be available after 10am IST.' },
        '127.0.0.1',
      );

      expect(result).toBe(updatedRow);
      expect(appMaintenanceRepo.update).toHaveBeenCalledWith(
        { enabled: true, message: 'App is in maintenance mode, it will be available after 10am IST.' },
        'admin-1',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'app_maintenance_updated',
          entityType: 'app_maintenance',
          beforeValue: { enabled: false, message: null },
          afterValue: {
            enabled: true,
            message: 'App is in maintenance mode, it will be available after 10am IST.',
          },
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });
});
