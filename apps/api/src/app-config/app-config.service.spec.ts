import { AppConfigService } from './app-config.service';

describe('AppConfigService', () => {
  let service: AppConfigService;
  let appMinVersionsRepo: any;
  let appMaintenanceRepo: any;
  let auditService: any;

  const androidRow = {
    app: 'nursejobs',
    platform: 'android',
    min_version: '1.2.0',
    store_url: 'https://play.google.com/store/apps/details?id=com.vitacasahealth.nursejobs',
    update_message: 'Please update to continue using NurseJobs.',
    updated_by: 'admin-1',
    updated_at: new Date(),
  };

  const maintenanceRow = {
    app: 'nursejobs',
    enabled: false,
    message: null,
    updated_by: null,
    updated_at: new Date(),
  };

  beforeEach(() => {
    appMinVersionsRepo = {
      findByAppAndPlatform: jest.fn(),
      findAll: jest.fn(),
      update: jest.fn(),
    };
    appMaintenanceRepo = {
      findByApp: jest.fn(),
      findAll: jest.fn(),
      update: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new AppConfigService(appMinVersionsRepo, appMaintenanceRepo, auditService);
  });

  describe('checkVersion', () => {
    it('throws GEN_002 for an unrecognized app/platform combination', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(null);
      await expect(service.checkVersion('nursejobs' as any, 'android' as any, '1.0.0')).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('requires an update when the installed version is below min_version', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('nursejobs' as any, 'android' as any, '1.1.0');
      expect(result).toEqual({
        update_required: true,
        min_version: '1.2.0',
        store_url: androidRow.store_url,
        update_message: androidRow.update_message,
      });
      expect(appMinVersionsRepo.findByAppAndPlatform).toHaveBeenCalledWith('nursejobs', 'android');
    });

    it('does not require an update when the installed version equals min_version', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('nursejobs' as any, 'android' as any, '1.2.0');
      expect(result.update_required).toBe(false);
      expect(result.store_url).toBeNull();
      expect(result.update_message).toBeNull();
    });

    it('does not require an update when the installed version is above min_version', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('nursejobs' as any, 'android' as any, '2.0.0');
      expect(result.update_required).toBe(false);
    });

    it('compares minor/patch correctly, not lexicographically (2.10.0 beats 2.9.0)', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue({ ...androidRow, min_version: '2.10.0' });
      const result = await service.checkVersion('nursejobs' as any, 'android' as any, '2.9.0');
      expect(result.update_required).toBe(true);
    });

    it('treats a malformed current version as 0.0.0 rather than throwing', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(androidRow);
      const result = await service.checkVersion('nursejobs' as any, 'android' as any, 'not-a-version');
      expect(result.update_required).toBe(true);
    });

    it('treats nursejobs and nursenow as fully independent — a nursenow row never satisfies a nursejobs lookup', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(null);
      await expect(service.checkVersion('nursenow' as any, 'android' as any, '1.0.0')).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(appMinVersionsRepo.findByAppAndPlatform).toHaveBeenCalledWith('nursenow', 'android');
    });
  });

  describe('adminList', () => {
    it('returns every app/platform row from the repository', async () => {
      appMinVersionsRepo.findAll.mockResolvedValue([androidRow]);
      const result = await service.adminList();
      expect(result).toEqual([androidRow]);
    });
  });

  describe('adminUpdate', () => {
    it('throws GEN_002 for an unrecognized app/platform combination', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(null);
      await expect(
        service.adminUpdate('admin-1', 'nursejobs', 'windows', { min_version: '1.0.0' }, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
      expect(appMinVersionsRepo.update).not.toHaveBeenCalled();
    });

    it('updates the row and audit-logs before/after values', async () => {
      appMinVersionsRepo.findByAppAndPlatform.mockResolvedValue(androidRow);
      const updatedRow = { ...androidRow, min_version: '1.3.0' };
      appMinVersionsRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminUpdate(
        'admin-1',
        'nursejobs',
        'android',
        { min_version: '1.3.0', store_url: 'https://play.google.com/x' },
        '127.0.0.1',
      );

      expect(result).toBe(updatedRow);
      expect(appMinVersionsRepo.update).toHaveBeenCalledWith(
        'nursejobs',
        'android',
        { min_version: '1.3.0', store_url: 'https://play.google.com/x' },
        'admin-1',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'app_version_updated',
          entityType: 'app_min_versions',
          beforeValue: { app: 'nursejobs', platform: 'android', min_version: '1.2.0', store_url: androidRow.store_url },
          afterValue: { app: 'nursejobs', platform: 'android', min_version: '1.3.0', store_url: 'https://play.google.com/x' },
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });

  describe('checkMaintenance', () => {
    it('throws GEN_002 for an unrecognized app', async () => {
      appMaintenanceRepo.findByApp.mockResolvedValue(null);
      await expect(service.checkMaintenance('nursejobs' as any)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns enabled: false and no message when maintenance is off', async () => {
      appMaintenanceRepo.findByApp.mockResolvedValue(maintenanceRow);
      const result = await service.checkMaintenance('nursejobs' as any);
      expect(result).toEqual({ enabled: false, message: null });
    });

    it('returns the message when maintenance is on', async () => {
      appMaintenanceRepo.findByApp.mockResolvedValue({
        ...maintenanceRow,
        enabled: true,
        message: 'App is in maintenance mode, it will be available after 10am IST.',
      });
      const result = await service.checkMaintenance('nursejobs' as any);
      expect(result).toEqual({
        enabled: true,
        message: 'App is in maintenance mode, it will be available after 10am IST.',
      });
    });

    it('suppresses a stale message once maintenance is turned back off', async () => {
      appMaintenanceRepo.findByApp.mockResolvedValue({
        ...maintenanceRow,
        enabled: false,
        message: 'Old message left over from a previous maintenance window.',
      });
      const result = await service.checkMaintenance('nursejobs' as any);
      expect(result.message).toBeNull();
    });
  });

  describe('adminMaintenanceList', () => {
    it('returns every app row from the repository', async () => {
      appMaintenanceRepo.findAll.mockResolvedValue([maintenanceRow]);
      const result = await service.adminMaintenanceList();
      expect(result).toEqual([maintenanceRow]);
    });
  });

  describe('adminMaintenanceUpdate', () => {
    it('throws GEN_002 for an unrecognized app', async () => {
      appMaintenanceRepo.findByApp.mockResolvedValue(null);
      await expect(
        service.adminMaintenanceUpdate('admin-1', 'windows', { enabled: true }, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
      expect(appMaintenanceRepo.update).not.toHaveBeenCalled();
    });

    it('updates the row and audit-logs before/after values', async () => {
      appMaintenanceRepo.findByApp.mockResolvedValue(maintenanceRow);
      const updatedRow = {
        ...maintenanceRow,
        enabled: true,
        message: 'App is in maintenance mode, it will be available after 10am IST.',
      };
      appMaintenanceRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminMaintenanceUpdate(
        'admin-1',
        'nursejobs',
        { enabled: true, message: 'App is in maintenance mode, it will be available after 10am IST.' },
        '127.0.0.1',
      );

      expect(result).toBe(updatedRow);
      expect(appMaintenanceRepo.update).toHaveBeenCalledWith(
        'nursejobs',
        { enabled: true, message: 'App is in maintenance mode, it will be available after 10am IST.' },
        'admin-1',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'app_maintenance_updated',
          entityType: 'app_maintenance',
          beforeValue: { app: 'nursejobs', enabled: false, message: null },
          afterValue: {
            app: 'nursejobs',
            enabled: true,
            message: 'App is in maintenance mode, it will be available after 10am IST.',
          },
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });
});
