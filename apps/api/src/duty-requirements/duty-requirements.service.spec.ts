import { DutyRequirementsService } from './duty-requirements.service';

describe('DutyRequirementsService', () => {
  let service: DutyRequirementsService;
  let dutyRequirementsRepo: any;
  let auditService: any;

  const existingRow = {
    id: 1,
    live_in: ['Bed, bedsheet, pillow and blanket must be provided.', '3 meals daily for the nurse.'],
    day_duty: ['Breakfast and lunch for the nurse.'],
    night_duty: ['Dinner and breakfast for the nurse.'],
    updated_by: null,
    updated_at: new Date(),
  };

  const validDto = {
    live_in: existingRow.live_in,
    day_duty: existingRow.day_duty,
    night_duty: existingRow.night_duty,
  };

  beforeEach(() => {
    dutyRequirementsRepo = { find: jest.fn(), findWithUpdater: jest.fn(), update: jest.fn() };
    auditService = { log: jest.fn() };
    service = new DutyRequirementsService(dutyRequirementsRepo, auditService);
  });

  describe('get', () => {
    it('returns the singleton row from the repository', async () => {
      dutyRequirementsRepo.find.mockResolvedValue(existingRow);
      const result = await service.get();
      expect(result).toBe(existingRow);
    });
  });

  describe('adminGet', () => {
    it('returns the row joined with the updater name', async () => {
      const withUpdater = { ...existingRow, updated_by_name: 'Admin One' };
      dutyRequirementsRepo.findWithUpdater.mockResolvedValue(withUpdater);
      const result = await service.adminGet();
      expect(result).toBe(withUpdater);
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs before/after lists', async () => {
      dutyRequirementsRepo.find.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, live_in: ['New bullet'] };
      dutyRequirementsRepo.update.mockResolvedValue(updatedRow);

      const dto = { ...validDto, live_in: ['New bullet'] };
      const result = await service.adminUpdate('admin-1', dto, '127.0.0.1');

      expect(result).toBe(updatedRow);
      expect(dutyRequirementsRepo.update).toHaveBeenCalledWith(dto, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'duty_requirements_updated',
          entityType: 'duty_requirements',
          beforeValue: {
            live_in: existingRow.live_in,
            day_duty: existingRow.day_duty,
            night_duty: existingRow.night_duty,
          },
          afterValue: {
            live_in: ['New bullet'],
            day_duty: existingRow.day_duty,
            night_duty: existingRow.night_duty,
          },
          ipAddress: '127.0.0.1',
        }),
      );
    });

    it.each([
      ['live_in empty', { ...validDto, live_in: [] }],
      ['day_duty empty', { ...validDto, day_duty: [] }],
      ['night_duty empty', { ...validDto, night_duty: [] }],
      ['live_in has a blank bullet', { ...validDto, live_in: ['fine', '   '] }],
      ['night_duty has an empty-string bullet', { ...validDto, night_duty: ['fine', ''] }],
    ])('throws DUTY_001 for %s', async (_label, malformedDto) => {
      await expect(service.adminUpdate('admin-1', malformedDto as any, null)).rejects.toMatchObject({
        code: 'DUTY_001',
      });
      expect(dutyRequirementsRepo.update).not.toHaveBeenCalled();
    });
  });
});
