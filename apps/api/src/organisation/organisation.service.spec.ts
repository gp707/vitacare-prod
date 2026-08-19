import { OrganisationService } from './organisation.service';

describe('OrganisationService', () => {
  let service: OrganisationService;
  let organisationProfilesRepo: any;
  let usersRepo: any;
  let auditService: any;

  beforeEach(() => {
    organisationProfilesRepo = { findByUserId: jest.fn() };
    usersRepo = {
      findById: jest.fn(),
      findByPhone: jest.fn(),
      updatePhone: jest.fn(),
      updateCodeHash: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new OrganisationService(organisationProfilesRepo, usersRepo, auditService);
  });

  describe('getMe', () => {
    it('throws GEN_002 when the user does not exist', async () => {
      usersRepo.findById.mockResolvedValue(null);
      await expect(service.getMe('user-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws GEN_002 when no organisation profile exists', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      organisationProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.getMe('user-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns identity + location + job-posting-blocked state', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      organisationProfilesRepo.findByUserId.mockResolvedValue({
        organisation_name: 'City Hospital',
        contact_person_name: 'Ravi Sharma',
        organisation_type: 'hospital',
        city: 'bangalore',
        area: 'Indiranagar',
        is_job_posting_blocked: true,
      });
      const result = await service.getMe('user-1');
      expect(result).toEqual({
        user_id: 'user-1',
        organisation_name: 'City Hospital',
        contact_person_name: 'Ravi Sharma',
        organisation_type: 'hospital',
        city: 'bangalore',
        area: 'Indiranagar',
        phone: '+919876543210',
        is_job_posting_blocked: true,
      });
    });
  });

  describe('updatePhone', () => {
    it('throws GEN_002 when no organisation profile exists', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(
        service.updatePhone('user-1', { phone: '+919876543210' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('is a no-op when the phone is unchanged', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      const result = await service.updatePhone('user-1', { phone: '+919876543210' } as any, null);
      expect(result).toEqual({ message: 'Phone number updated' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('throws AUTH_001 when the new phone is already taken', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      usersRepo.findByPhone.mockResolvedValue({ id: 'someone-else' });
      await expect(
        service.updatePhone('user-1', { phone: '+919876500000' } as any, null),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
    });

    it('updates the phone and audit-logs it when it is new and unused', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      usersRepo.findByPhone.mockResolvedValue(null);

      const result = await service.updatePhone('user-1', { phone: '+919876500000' } as any, '127.0.0.1');

      expect(usersRepo.updatePhone).toHaveBeenCalledWith('user-1', '+919876500000');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'phone_changed',
          entityType: 'organisation_profiles',
          entityId: 'op-1',
        }),
      );
      expect(result).toEqual({ message: 'Phone number updated' });
    });
  });

  describe('updateCode', () => {
    it('throws GEN_002 when no organisation profile exists', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.updateCode('user-1', { code: '1234' } as any, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('hashes and stores the new code, and audit-logs it', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      const result = await service.updateCode('user-1', { code: '4321' } as any, '127.0.0.1');

      expect(usersRepo.updateCodeHash).toHaveBeenCalledWith('user-1', expect.any(String));
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'code_changed', entityType: 'organisation_profiles' }),
      );
      expect(result).toEqual({ message: 'Login code updated' });
    });
  });
});
