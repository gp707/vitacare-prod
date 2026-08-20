import { AdminOrganisationsService } from './admin-organisations.service';

describe('AdminOrganisationsService', () => {
  let service: AdminOrganisationsService;
  let organisationsRepo: any;
  let usersRepo: any;
  let auditService: any;

  beforeEach(() => {
    organisationsRepo = {
      listOrganisations: jest.fn(),
      findDetailByUserId: jest.fn(),
      setJobPostingBlocked: jest.fn(),
      setBlockReason: jest.fn(),
    };
    usersRepo = { setActive: jest.fn() };
    auditService = { log: jest.fn() };
    service = new AdminOrganisationsService(organisationsRepo, usersRepo, auditService);
  });

  describe('listOrganisations', () => {
    it('paginates and shapes meta correctly', async () => {
      organisationsRepo.listOrganisations.mockResolvedValue({ items: [{ user_id: 'u1' }], total: 25 });
      const result = await service.listOrganisations({ page: 2, limit: 10 } as any);
      expect(organisationsRepo.listOrganisations).toHaveBeenCalledWith(
        { search: undefined, blockStatus: undefined, organisationType: undefined, city: undefined },
        { page: 2, limit: 10 },
      );
      expect(result.data).toEqual([{ user_id: 'u1' }]);
      expect(result.meta).toEqual({ page: 2, limit: 10, total: 25, totalPages: 3 });
    });

    it('passes search/block_status/organisation_type/city filters through', async () => {
      organisationsRepo.listOrganisations.mockResolvedValue({ items: [], total: 0 });
      await service.listOrganisations({
        page: 1,
        limit: 20,
        search: 'ORG-500',
        block_status: 'job_posting_blocked',
        organisation_type: 'hospital',
        city: 'bangalore',
      } as any);
      expect(organisationsRepo.listOrganisations).toHaveBeenCalledWith(
        { search: 'ORG-500', blockStatus: 'job_posting_blocked', organisationType: 'hospital', city: 'bangalore' },
        { page: 1, limit: 20 },
      );
    });
  });

  describe('getOrganisationDetail', () => {
    it('throws GEN_002 when not found', async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue(null);
      await expect(service.getOrganisationDetail('u1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns the organisation detail', async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      const result = await service.getOrganisationDetail('u1');
      expect(result).toEqual({ user_id: 'u1' });
    });
  });

  describe('block', () => {
    it('throws GEN_002 when the organisation does not exist', async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue(null);
      await expect(
        service.block('u1', { level: 'full', reason: 'x' }, 'admin-1', null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it("level 'full' deactivates the user and stores the reason, without touching is_job_posting_blocked", async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.block('u1', { level: 'full', reason: 'Fraudulent postings' }, 'admin-1', '127.0.0.1');
      expect(usersRepo.setActive).toHaveBeenCalledWith('u1', false);
      expect(organisationsRepo.setBlockReason).toHaveBeenCalledWith('u1', 'Fraudulent postings');
      expect(organisationsRepo.setJobPostingBlocked).not.toHaveBeenCalled();
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', targetUserId: 'u1', action: 'status_changed' }),
      );
    });

    it("level 'job_posting' only flags is_job_posting_blocked, without touching users.is_active", async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.block('u1', { level: 'job_posting', reason: 'Suspicious activity' }, 'admin-1', null);
      expect(organisationsRepo.setJobPostingBlocked).toHaveBeenCalledWith('u1', true, 'Suspicious activity');
      expect(usersRepo.setActive).not.toHaveBeenCalled();
    });
  });

  describe('unblock', () => {
    it("level 'full' reactivates the user and clears the reason", async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.unblock('u1', 'full', 'admin-1', null);
      expect(usersRepo.setActive).toHaveBeenCalledWith('u1', true);
      expect(organisationsRepo.setBlockReason).toHaveBeenCalledWith('u1', null);
    });

    it("level 'job_posting' clears is_job_posting_blocked and the reason", async () => {
      organisationsRepo.findDetailByUserId.mockResolvedValue({ user_id: 'u1' });
      await service.unblock('u1', 'job_posting', 'admin-1', null);
      expect(organisationsRepo.setJobPostingBlocked).toHaveBeenCalledWith('u1', false, null);
    });
  });
});
