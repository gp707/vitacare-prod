import { InsightsService } from './insights.service';

describe('InsightsService — who is on which app version', () => {
  let service: InsightsService;
  let insightsRepo: any;

  beforeEach(() => {
    insightsRepo = {
      appVersionSummary: jest.fn(),
      listAccountsByAppVersion: jest.fn(),
    };
    service = new InsightsService({} as any, insightsRepo, {} as any);
  });

  describe('summary', () => {
    it('passes the counts, the minimums and the not-reported count through, and totals the accounts below the minimum', async () => {
      insightsRepo.appVersionSummary.mockResolvedValue({
        minimums: [{ platform: 'android', min_version: '1.0.2', audience_mode: 'all', audience_categories: [], audience_user_count: 0 }],
        versions: [
          { platform: 'android', version: '1.1.0', total: 10, caregivers: 6, patients: 3, organisations: 1, below_minimum: false },
          { platform: 'android', version: '1.0.0', total: 4, caregivers: 3, patients: 1, organisations: 0, below_minimum: true },
          { platform: 'ios', version: '0.9.0', total: 2, caregivers: 0, patients: 2, organisations: 0, below_minimum: true },
        ],
        notReported: { total: 7, caregivers: 4, patients: 2, organisations: 1 },
      });
      const result = await service.getAppVersionSummary();
      expect(result.minimums).toHaveLength(1);
      expect(result.versions).toHaveLength(3);
      expect(result.not_reported).toEqual({ total: 7, caregivers: 4, patients: 2, organisations: 1 });
      expect(result.below_minimum_total).toBe(6); // 4 + 2
    });

    it('reports zero below-minimum when everyone is up to date', async () => {
      insightsRepo.appVersionSummary.mockResolvedValue({
        minimums: [],
        versions: [{ platform: 'android', version: '2.0.0', total: 5, caregivers: 5, patients: 0, organisations: 0, below_minimum: false }],
        notReported: { total: 0, caregivers: 0, patients: 0, organisations: 0 },
      });
      expect((await service.getAppVersionSummary()).below_minimum_total).toBe(0);
    });
  });

  describe('accounts list', () => {
    it('passes every filter to the query and pages the result', async () => {
      insightsRepo.listAccountsByAppVersion.mockResolvedValue({ items: [{ user_id: 'u1' }], total: 41 });
      const result = await service.listAppVersionAccounts({
        page: 2,
        limit: 20,
        platform: 'android',
        version: '1.0.0',
        role: 'caregiver',
        status: 'below_minimum',
      });
      expect(insightsRepo.listAccountsByAppVersion).toHaveBeenCalledWith({
        page: 2,
        limit: 20,
        platform: 'android',
        version: '1.0.0',
        role: 'caregiver',
        status: 'below_minimum',
      });
      expect(result.data).toEqual([{ user_id: 'u1' }]);
      expect(result.meta).toEqual({ page: 2, limit: 20, total: 41, totalPages: 3 });
    });
  });
});
