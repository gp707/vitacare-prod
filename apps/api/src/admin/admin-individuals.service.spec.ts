import { AdminIndividualsService } from './admin-individuals.service';

describe('AdminIndividualsService', () => {
  let service: AdminIndividualsService;
  let individualsRepo: any;
  let usersRepo: any;
  let auditService: any;

  beforeEach(() => {
    individualsRepo = {
      listIndividuals: jest.fn(),
      findDetailByUserId: jest.fn(),
      setJobPostingBlocked: jest.fn(),
      setBlockReason: jest.fn(),
    };
    usersRepo = { setActive: jest.fn() };
    auditService = { log: jest.fn() };
    service = new AdminIndividualsService(individualsRepo, usersRepo, auditService);
  });

  describe('listIndividuals', () => {
    it('paginates and shapes meta correctly', async () => {
      individualsRepo.listIndividuals.mockResolvedValue({ items: [{ user_id: 'u1' }], total: 25 });
      const result = await service.listIndividuals({ page: 2, limit: 10 } as any);
      expect(individualsRepo.listIndividuals).toHaveBeenCalledWith(
        { search: undefined, blockStatus: undefined },
        { page: 2, limit: 10 },
      );
      expect(result.data).toEqual([{ user_id: 'u1' }]);
      expect(result.meta).toEqual({ page: 2, limit: 10, total: 25, totalPages: 3 });
    });

    it('passes search and block_status filters through', async () => {
      individualsRepo.listIndividuals.mockResolvedValue({ items: [], total: 0 });
      await service.listIndividuals({ page: 1, limit: 20, search: 'PAT-500', block_status: 'blocked' } as any);
      expect(individualsRepo.listIndividuals).toHaveBeenCalledWith(
        { search: 'PAT-500', blockStatus: 'blocked' },
        { page: 1, limit: 20 },
      );
    });
  });

  describe('getIndividualDetail', () => {
    it('throws GEN_002 when not found', async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue(null);
      await expect(service.getIndividualDetail('u1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns the individual detail', async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      const result = await service.getIndividualDetail('u1');
      expect(result).toEqual({ user_id: 'u1' });
    });
  });

  describe('block', () => {
    it('throws GEN_002 when the individual does not exist', async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue(null);
      await expect(
        service.block('u1', { level: 'full', reason: 'x' }, 'admin-1', null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it("level 'full' deactivates the user and stores the reason, without touching is_job_posting_blocked", async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.block('u1', { level: 'full', reason: 'Fraudulent postings' }, 'admin-1', '127.0.0.1');
      expect(usersRepo.setActive).toHaveBeenCalledWith('u1', false);
      expect(individualsRepo.setBlockReason).toHaveBeenCalledWith('u1', 'Fraudulent postings');
      expect(individualsRepo.setJobPostingBlocked).not.toHaveBeenCalled();
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', targetUserId: 'u1', action: 'status_changed' }),
      );
    });

    it("level 'job_posting' only flags is_job_posting_blocked, without touching users.is_active", async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.block('u1', { level: 'job_posting', reason: 'Suspicious activity' }, 'admin-1', null);
      expect(individualsRepo.setJobPostingBlocked).toHaveBeenCalledWith('u1', true, 'Suspicious activity');
      expect(usersRepo.setActive).not.toHaveBeenCalled();
    });
  });

  describe('unblock', () => {
    it("level 'full' reactivates the user and clears the reason", async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.unblock('u1', 'full', 'admin-1', null);
      expect(usersRepo.setActive).toHaveBeenCalledWith('u1', true);
      expect(individualsRepo.setBlockReason).toHaveBeenCalledWith('u1', null);
    });

    it("level 'job_posting' clears is_job_posting_blocked and the reason", async () => {
      individualsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.unblock('u1', 'job_posting', 'admin-1', null);
      expect(individualsRepo.setJobPostingBlocked).toHaveBeenCalledWith('u1', false, null);
    });
  });
});
