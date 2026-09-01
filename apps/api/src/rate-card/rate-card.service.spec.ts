import { RateCardService } from './rate-card.service';

describe('RateCardService', () => {
  let service: RateCardService;
  let rateCardRepo: any;
  let auditService: any;

  const dailyRow = {
    frequency_of_care: 'daily',
    title: 'Salary Guidelines — Daily',
    column_labels: ['Companion care', 'Bedside Care', 'Critical Care'],
    row_labels: ['Care'],
    cells: [['867 per day', '933 per day', 'Caregivers are not suggested']],
    updated_by: null,
    updated_at: new Date(),
  };

  const monthlyRow = { ...dailyRow, frequency_of_care: 'monthly', title: 'Salary Guidelines — Monthly' };

  const validDto = {
    title: dailyRow.title,
    column_labels: dailyRow.column_labels,
    row_labels: dailyRow.row_labels,
    cells: dailyRow.cells,
  };

  beforeEach(() => {
    rateCardRepo = {
      findByFrequency: jest.fn(),
      findAll: jest.fn(),
      findAllWithUpdater: jest.fn(),
      update: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new RateCardService(rateCardRepo, auditService);
  });

  describe('get', () => {
    it('returns both frequency rows from the repository', async () => {
      rateCardRepo.findAll.mockResolvedValue([dailyRow, monthlyRow]);
      const result = await service.get();
      expect(result).toEqual([dailyRow, monthlyRow]);
    });
  });

  describe('adminGet', () => {
    it('returns both rows joined with the updater name', async () => {
      const withUpdater = [
        { ...dailyRow, updated_by_name: 'Admin One' },
        { ...monthlyRow, updated_by_name: 'Admin One' },
      ];
      rateCardRepo.findAllWithUpdater.mockResolvedValue(withUpdater);
      const result = await service.adminGet();
      expect(result).toBe(withUpdater);
    });
  });

  describe('adminUpdate', () => {
    it('updates the row for the given frequency and audit-logs before/after title and cells', async () => {
      rateCardRepo.findByFrequency.mockResolvedValue(dailyRow);
      const updatedRow = { ...dailyRow, title: 'New Title' };
      rateCardRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminUpdate('admin-1', 'daily', { ...validDto, title: 'New Title' }, '127.0.0.1');

      expect(result).toBe(updatedRow);
      expect(rateCardRepo.update).toHaveBeenCalledWith('daily', { ...validDto, title: 'New Title' }, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'rate_card_updated',
          entityType: 'rate_card',
          beforeValue: { frequency_of_care: 'daily', title: dailyRow.title, cells: dailyRow.cells },
          afterValue: { frequency_of_care: 'daily', title: 'New Title', cells: validDto.cells },
          ipAddress: '127.0.0.1',
        }),
      );
    });

    it('throws GEN_002 for an unrecognized frequency', async () => {
      rateCardRepo.findByFrequency.mockResolvedValue(null);
      await expect(service.adminUpdate('admin-1', 'yearly', validDto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(rateCardRepo.update).not.toHaveBeenCalled();
    });

    it.each([
      ['no rows', []],
      ['too many rows', [...validDto.cells, ['a', 'b', 'c']]],
      ['a row with too few columns', [['a', 'b']]],
      ['a row with a non-string cell', [[1, 'b', 'c']]],
      ['not an array of arrays', ['not-a-row']],
    ])('throws RATE_001 for %s', async (_label, malformedCells) => {
      rateCardRepo.findByFrequency.mockResolvedValue(dailyRow);
      await expect(
        service.adminUpdate('admin-1', 'daily', { ...validDto, cells: malformedCells as any }, null),
      ).rejects.toMatchObject({ code: 'RATE_001' });
      expect(rateCardRepo.update).not.toHaveBeenCalled();
    });
  });
});
