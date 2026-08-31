import { ScopeOfWorkService } from './scope-of-work.service';

describe('ScopeOfWorkService', () => {
  let service: ScopeOfWorkService;
  let scopeOfWorkRepo: any;
  let auditService: any;

  const existingRow = {
    id: 1,
    companion_care: ['Emotional companionship', 'Walking & mobility support'],
    bedside_care: ['Diaper changing & hygiene care', 'Feeding assistance'],
    critical_care: ['Catheter care', 'Vitals monitoring'],
    updated_by: null,
    updated_at: new Date(),
  };

  const validDto = {
    companion_care: existingRow.companion_care,
    bedside_care: existingRow.bedside_care,
    critical_care: existingRow.critical_care,
  };

  beforeEach(() => {
    scopeOfWorkRepo = { find: jest.fn(), findWithUpdater: jest.fn(), update: jest.fn() };
    auditService = { log: jest.fn() };
    service = new ScopeOfWorkService(scopeOfWorkRepo, auditService);
  });

  describe('get', () => {
    it('returns the singleton row from the repository', async () => {
      scopeOfWorkRepo.find.mockResolvedValue(existingRow);
      const result = await service.get();
      expect(result).toBe(existingRow);
    });
  });

  describe('adminGet', () => {
    it('returns the row joined with the updater name', async () => {
      const withUpdater = { ...existingRow, updated_by_name: 'Admin One' };
      scopeOfWorkRepo.findWithUpdater.mockResolvedValue(withUpdater);
      const result = await service.adminGet();
      expect(result).toBe(withUpdater);
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs before/after tiers', async () => {
      scopeOfWorkRepo.find.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, companion_care: ['New bullet'] };
      scopeOfWorkRepo.update.mockResolvedValue(updatedRow);

      const dto = { ...validDto, companion_care: ['New bullet'] };
      const result = await service.adminUpdate('admin-1', dto, '127.0.0.1');

      expect(result).toBe(updatedRow);
      expect(scopeOfWorkRepo.update).toHaveBeenCalledWith(dto, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'scope_of_work_updated',
          entityType: 'scope_of_work',
          beforeValue: {
            companion_care: existingRow.companion_care,
            bedside_care: existingRow.bedside_care,
            critical_care: existingRow.critical_care,
          },
          afterValue: {
            companion_care: ['New bullet'],
            bedside_care: existingRow.bedside_care,
            critical_care: existingRow.critical_care,
          },
          ipAddress: '127.0.0.1',
        }),
      );
    });

    it.each([
      ['companion_care empty', { ...validDto, companion_care: [] }],
      ['bedside_care empty', { ...validDto, bedside_care: [] }],
      ['critical_care empty', { ...validDto, critical_care: [] }],
      ['companion_care has a blank bullet', { ...validDto, companion_care: ['fine', '   '] }],
      ['critical_care has an empty-string bullet', { ...validDto, critical_care: ['fine', ''] }],
    ])('throws SCOPE_001 for %s', async (_label, malformedDto) => {
      await expect(service.adminUpdate('admin-1', malformedDto as any, null)).rejects.toMatchObject({
        code: 'SCOPE_001',
      });
      expect(scopeOfWorkRepo.update).not.toHaveBeenCalled();
    });
  });
});
