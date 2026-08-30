import { RateCardService } from './rate-card.service';

describe('RateCardService', () => {
  let service: RateCardService;
  let rateCardRepo: any;
  let auditService: any;

  const existingRow = {
    id: 1,
    title: 'Salary Guidelines (12 hrs/24 hrs duty)',
    column_labels: ['Companion care', 'Bedside Care', 'Critical Care'],
    row_labels: ['Caregivers', 'Nursing students/Nursing with backlogs', 'Nurses'],
    cells: [
      ['26000 pm/867 per day', '28000 pm/933 per day', 'Caregivers are not suggested'],
      ['28000 pm/933 per day', '30000 pm/1000 per day', '32000 pm/1067 per day'],
      ['30000 pm/1000 per day', '32000 pm/1067 per day', '35000-42000 pm'],
    ],
    updated_by: null,
    updated_at: new Date(),
  };

  const validDto = {
    title: existingRow.title,
    column_labels: existingRow.column_labels,
    row_labels: existingRow.row_labels,
    cells: existingRow.cells,
  };

  beforeEach(() => {
    rateCardRepo = { find: jest.fn(), findWithUpdater: jest.fn(), update: jest.fn() };
    auditService = { log: jest.fn() };
    service = new RateCardService(rateCardRepo, auditService);
  });

  describe('get', () => {
    it('returns the singleton row from the repository', async () => {
      rateCardRepo.find.mockResolvedValue(existingRow);
      const result = await service.get();
      expect(result).toBe(existingRow);
    });
  });

  describe('adminGet', () => {
    it('returns the row joined with the updater name', async () => {
      const withUpdater = { ...existingRow, updated_by_name: 'Admin One' };
      rateCardRepo.findWithUpdater.mockResolvedValue(withUpdater);
      const result = await service.adminGet();
      expect(result).toBe(withUpdater);
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs before/after title and cells', async () => {
      rateCardRepo.find.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, title: 'New Title' };
      rateCardRepo.update.mockResolvedValue(updatedRow);

      const result = await service.adminUpdate('admin-1', { ...validDto, title: 'New Title' }, '127.0.0.1');

      expect(result).toBe(updatedRow);
      expect(rateCardRepo.update).toHaveBeenCalledWith({ ...validDto, title: 'New Title' }, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'rate_card_updated',
          entityType: 'rate_card',
          beforeValue: { title: existingRow.title, cells: existingRow.cells },
          afterValue: { title: 'New Title', cells: validDto.cells },
          ipAddress: '127.0.0.1',
        }),
      );
    });

    it.each([
      ['too few rows', [validDto.cells[0], validDto.cells[1]]],
      ['too many rows', [...validDto.cells, ['a', 'b', 'c']]],
      ['a row with too few columns', [['a', 'b'], validDto.cells[1], validDto.cells[2]]],
      ['a row with a non-string cell', [[1, 'b', 'c'], validDto.cells[1], validDto.cells[2]]],
      ['not an array of arrays', ['not-a-row', 'also-not', 'nope']],
    ])('throws RATE_001 for %s', async (_label, malformedCells) => {
      await expect(
        service.adminUpdate('admin-1', { ...validDto, cells: malformedCells as any }, null),
      ).rejects.toMatchObject({ code: 'RATE_001' });
      expect(rateCardRepo.update).not.toHaveBeenCalled();
    });
  });
});
