import { AppConfigService } from './app-config.service';

describe('AppConfigService', () => {
  let service: AppConfigService;
  let appMinVersionsRepo: any;
  let appMaintenanceRepo: any;
  let auditService: any;
  let accountSearchRepo: any;
  let usersRepo: any;

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
      categoryOfUser: jest.fn(),
    };
    appMaintenanceRepo = {
      find: jest.fn(),
      findWithUpdater: jest.fn(),
      update: jest.fn(),
    };
    auditService = { log: jest.fn() };
    accountSearchRepo = { search: jest.fn().mockResolvedValue([]), countExisting: jest.fn().mockResolvedValue(0) };
    usersRepo = { recordAppVersion: jest.fn().mockResolvedValue(undefined) };
    service = new AppConfigService(appMinVersionsRepo, appMaintenanceRepo, auditService, accountSearchRepo, usersRepo);
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
        { min_version: '1.3.0', store_url: 'https://play.google.com/x', audience: undefined },
        'admin-1',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'app_version_updated',
          entityType: 'app_min_versions',
          beforeValue: expect.objectContaining({ platform: 'android', min_version: '1.2.0', store_url: androidRow.store_url }),
          afterValue: expect.objectContaining({ platform: 'android', min_version: '1.3.0', store_url: 'https://play.google.com/x' }),
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

  describe('who a minimum version applies to', () => {
    const selectedRow = (over: Record<string, unknown> = {}) => ({
      ...androidRow,
      audience_mode: 'selected',
      audience_categories: [],
      audience_user_ids: [],
      ...over,
    });
    const check = (row: any, caller?: string | null, version = '1.0.0') => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(row);
      return service.checkVersion('android' as any, version, caller);
    };

    it('"all" (and a row that predates audiences) binds everyone, signed in or not', async () => {
      expect((await check({ ...androidRow, audience_mode: 'all' })).update_required).toBe(true);
      expect((await check({ ...androidRow, audience_mode: 'all' }, 'someone')).update_required).toBe(true);
      expect((await check(androidRow)).update_required).toBe(true); // no audience columns at all
    });

    it('a selected audience never blocks an anonymous caller (the app asks again after sign-in)', async () => {
      const result = await check(selectedRow({ audience_categories: ['caregiver'] }), null);
      expect(result.update_required).toBe(false);
      expect(result.store_url).toBeNull();
      expect(result.update_message).toBeNull();
      expect(appMinVersionsRepo.categoryOfUser).not.toHaveBeenCalled();
    });

    it('binds a caregiver when "caregivers" is selected, and nobody else', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('caregiver');
      expect((await check(selectedRow({ audience_categories: ['caregiver'] }), 'u1')).update_required).toBe(true);
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('individual');
      expect((await check(selectedRow({ audience_categories: ['caregiver'] }), 'u2')).update_required).toBe(false);
    });

    it.each(['hospital', 'rehab', 'clinic', 'agency'])('an organisation of type %s is bound only when that type is selected', async (type) => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue(type);
      expect((await check(selectedRow({ audience_categories: [type] }), 'org')).update_required).toBe(true);
      const others = ['hospital', 'rehab', 'clinic', 'agency'].filter((t) => t !== type);
      expect((await check(selectedRow({ audience_categories: others }), 'org')).update_required).toBe(false);
    });

    it('patients/families are their own category', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('individual');
      expect((await check(selectedRow({ audience_categories: ['individual'] }), 'p1')).update_required).toBe(true);
    });

    it('a specific account is bound by id even when its category is not selected', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('individual');
      const row = selectedRow({ audience_categories: ['caregiver'], audience_user_ids: ['p1'] });
      expect((await check(row, 'p1')).update_required).toBe(true);
      expect((await check(row, 'p2')).update_required).toBe(false);
    });

    it('categories and accounts add up (either one is enough)', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('caregiver');
      const row = selectedRow({ audience_categories: ['caregiver'], audience_user_ids: ['p1'] });
      expect((await check(row, 'c1')).update_required).toBe(true);
      expect((await check(row, 'p1')).update_required).toBe(true);
    });

    it('an admin (no audience category) is never bound by a selected audience', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue(null);
      expect((await check(selectedRow({ audience_categories: ['caregiver'] }), 'admin-1')).update_required).toBe(false);
    });

    it('a selected audience with nobody in it binds nobody', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('caregiver');
      expect((await check(selectedRow(), 'c1')).update_required).toBe(false);
    });

    it('someone in the audience who already has the minimum version (or newer) is not told to update', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('caregiver');
      const row = selectedRow({ audience_categories: ['caregiver'] }); // min 1.2.0
      expect((await check(row, 'c1', '1.2.0')).update_required).toBe(false);
      expect((await check(row, 'c1', '1.3.0')).update_required).toBe(false);
      expect((await check(row, 'c1', '1.1.9')).update_required).toBe(true);
    });

    it('the message and store link are only sent to someone who is actually bound', async () => {
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('caregiver');
      const bound = await check(selectedRow({ audience_categories: ['caregiver'] }), 'c1');
      expect(bound).toMatchObject({ update_required: true, store_url: androidRow.store_url, update_message: androidRow.update_message });
    });
  });

  describe('admin setting the audience', () => {
    const base = { min_version: '1.2.0' };
    beforeEach(() => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue({ ...androidRow, audience_mode: 'all', audience_categories: [], audience_user_ids: [] });
      appMinVersionsRepo.update.mockImplementation(async (_p: string, input: any) => ({
        ...androidRow,
        audience_mode: input.audience?.mode ?? 'all',
        audience_categories: input.audience?.categories ?? [],
        audience_user_ids: input.audience?.user_ids ?? [],
      }));
    });

    it('leaves the audience untouched when none is sent (an older admin-web)', async () => {
      await service.adminUpdate('admin-1', 'android', base as any, null);
      expect(appMinVersionsRepo.update).toHaveBeenCalledWith('android', expect.objectContaining({ audience: undefined }), 'admin-1');
    });

    it('"all" clears the categories and accounts', async () => {
      await service.adminUpdate('admin-1', 'android', { ...base, audience_mode: 'all', audience_categories: ['caregiver'], audience_user_ids: ['x'] } as any, null);
      expect(appMinVersionsRepo.update).toHaveBeenCalledWith('android', expect.objectContaining({ audience: { mode: 'all', categories: [], user_ids: [] } }), 'admin-1');
      expect(accountSearchRepo.countExisting).not.toHaveBeenCalled();
    });

    it('"selected" stores the categories and accounts, without duplicates, after checking the accounts exist', async () => {
      accountSearchRepo.countExisting.mockResolvedValue(2);
      await service.adminUpdate(
        'admin-1',
        'android',
        { ...base, audience_mode: 'selected', audience_categories: ['hospital', 'agency', 'hospital'], audience_user_ids: ['u1', 'u2', 'u1'] } as any,
        null,
      );
      expect(accountSearchRepo.countExisting).toHaveBeenCalledWith(['u1', 'u2']);
      expect(appMinVersionsRepo.update).toHaveBeenCalledWith(
        'android',
        expect.objectContaining({ audience: { mode: 'selected', categories: ['hospital', 'agency'], user_ids: ['u1', 'u2'] } }),
        'admin-1',
      );
    });

    it('refuses a selected audience with nobody in it (GEN_001)', async () => {
      await expect(service.adminUpdate('admin-1', 'android', { ...base, audience_mode: 'selected' } as any, null)).rejects.toMatchObject({ code: 'GEN_001' });
      expect(appMinVersionsRepo.update).not.toHaveBeenCalled();
    });

    it('refuses an account that does not exist (GEN_001)', async () => {
      accountSearchRepo.countExisting.mockResolvedValue(1);
      await expect(
        service.adminUpdate('admin-1', 'android', { ...base, audience_mode: 'selected', audience_user_ids: ['u1', 'ghost'] } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_001' });
      expect(appMinVersionsRepo.update).not.toHaveBeenCalled();
    });

    it('audit-logs the audience before and after', async () => {
      accountSearchRepo.countExisting.mockResolvedValue(1);
      await service.adminUpdate('admin-1', 'android', { ...base, audience_mode: 'selected', audience_categories: ['caregiver'], audience_user_ids: ['u1'] } as any, '1.1.1.1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: expect.objectContaining({ audience_mode: 'all', audience_user_count: 0 }),
          afterValue: expect.objectContaining({ audience_mode: 'selected', audience_categories: ['caregiver'], audience_user_count: 1 }),
        }),
      );
    });
  });

  describe('searching accounts for the audience picker', () => {
    it('needs at least 2 characters and never dumps the user base', async () => {
      expect(await service.searchAccounts(' a ', null)).toEqual([]);
      expect(accountSearchRepo.search).not.toHaveBeenCalled();
    });

    it('searches with the trimmed text and the optional category', async () => {
      accountSearchRepo.search.mockResolvedValue([{ user_id: 'u1' }]);
      expect(await service.searchAccounts('  asha ', 'caregiver')).toEqual([{ user_id: 'u1' }]);
      expect(accountSearchRepo.search).toHaveBeenCalledWith('asha', 'caregiver');
    });
  });

  describe('remembering which app version an account runs', () => {
    it('records the platform and version of a signed-in caller, whatever the audience', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue({ ...androidRow, audience_mode: 'selected', audience_categories: ['caregiver'], audience_user_ids: [] });
      appMinVersionsRepo.categoryOfUser.mockResolvedValue('individual'); // not in the audience: still recorded
      await service.checkVersion('android' as any, '1.4.2', 'patient-1');
      expect(usersRepo.recordAppVersion).toHaveBeenCalledWith('patient-1', 'android', '1.4.2');
    });

    it('records it even when the account is already up to date', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow); // min 1.2.0
      const result = await service.checkVersion('android' as any, '2.0.0', 'cg-1');
      expect(result.update_required).toBe(false);
      expect(usersRepo.recordAppVersion).toHaveBeenCalledWith('cg-1', 'android', '2.0.0');
    });

    it('records nothing for an anonymous caller (nobody to attach it to)', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      await service.checkVersion('android' as any, '1.0.0', null);
      await service.checkVersion('android' as any, '1.0.0');
      expect(usersRepo.recordAppVersion).not.toHaveBeenCalled();
    });

    it('a failing write never breaks or delays the check', async () => {
      appMinVersionsRepo.findByPlatform.mockResolvedValue(androidRow);
      usersRepo.recordAppVersion.mockRejectedValue(new Error('db down'));
      await expect(service.checkVersion('android' as any, '1.0.0', 'cg-1')).resolves.toMatchObject({ update_required: true });
    });
  });
});
