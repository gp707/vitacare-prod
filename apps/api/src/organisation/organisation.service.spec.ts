import * as bcrypt from 'bcrypt';
import { OrganisationService } from './organisation.service';

describe('OrganisationService', () => {
  let service: OrganisationService;
  let organisationProfilesRepo: any;
  let usersRepo: any;
  let auditService: any;

  beforeEach(() => {
    organisationProfilesRepo = { findByUserId: jest.fn(), update: jest.fn(), anonymizeContactPerson: jest.fn() };
    usersRepo = {
      findById: jest.fn(),
      findByPhoneAndRoles: jest.fn(),
      updatePhone: jest.fn(),
      updateCodeHash: jest.fn(),
      updateFullName: jest.fn(),
      updateFcmToken: jest.fn(),
      anonymizeAndDeactivate: jest.fn(),
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
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ id: 'someone-else' });
      await expect(
        service.updatePhone('user-1', { phone: '+919876500000' } as any, null),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
    });

    it('updates the phone and audit-logs it when it is new and unused', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);

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

  describe('updateProfile', () => {
    const profile = {
      id: 'op-1',
      organisation_name: 'City Hospital',
      organisation_type: 'hospital',
      city: 'bangalore',
      area: 'Indiranagar',
    };
    const user = { id: 'user-1', full_name: 'Ravi Sharma', phone: '+919876543210' };

    it('throws GEN_002 when no organisation profile exists', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(
        service.updateProfile('user-1', { organisation_name: 'New Name' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws GEN_002 when the user does not exist', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(profile);
      usersRepo.findById.mockResolvedValue(null);
      await expect(
        service.updateProfile('user-1', { organisation_name: 'New Name' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('updates every provided field, keeps full_name in sync across users and organisation_profiles, and '
      + 'audit-logs only what changed', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(profile);
      usersRepo.findById.mockResolvedValue(user);

      const result = await service.updateProfile(
        'user-1',
        {
          full_name: 'Priya Iyer',
          organisation_name: 'Green Valley Clinic',
          organisation_type: 'clinic',
          city: 'mumbai',
          area: 'Andheri',
        } as any,
        '127.0.0.1',
      );

      expect(usersRepo.updateFullName).toHaveBeenCalledWith('user-1', 'Priya Iyer');
      expect(organisationProfilesRepo.update).toHaveBeenCalledWith('user-1', {
        organisation_name: 'Green Valley Clinic',
        contact_person_name: 'Priya Iyer',
        organisation_type: 'clinic',
        city: 'mumbai',
        area: 'Andheri',
      });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'profile_updated',
          entityType: 'organisation_profiles',
          entityId: 'op-1',
          beforeValue: {
            full_name: 'Ravi Sharma',
            organisation_name: 'City Hospital',
            organisation_type: 'hospital',
            city: 'bangalore',
            area: 'Indiranagar',
          },
          afterValue: {
            full_name: 'Priya Iyer',
            organisation_name: 'Green Valley Clinic',
            organisation_type: 'clinic',
            city: 'mumbai',
            area: 'Andheri',
          },
        }),
      );
      expect(result).toEqual({ message: 'Profile updated' });
    });

    it('updates only the one field provided, leaving the rest untouched', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(profile);
      usersRepo.findById.mockResolvedValue(user);

      await service.updateProfile('user-1', { area: 'Whitefield' } as any, null);

      expect(usersRepo.updateFullName).not.toHaveBeenCalled();
      expect(organisationProfilesRepo.update).toHaveBeenCalledWith('user-1', {
        organisation_name: undefined,
        contact_person_name: undefined,
        organisation_type: undefined,
        city: undefined,
        area: 'Whitefield',
      });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ beforeValue: { area: 'Indiranagar' }, afterValue: { area: 'Whitefield' } }),
      );
    });

    it('does not audit-log when every provided value is unchanged', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(profile);
      usersRepo.findById.mockResolvedValue(user);

      await service.updateProfile('user-1', { organisation_name: 'City Hospital' } as any, null);

      expect(auditService.log).not.toHaveBeenCalled();
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

  describe('deleteAccount', () => {
    it('throws GEN_002 when no organisation profile exists', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.deleteAccount('user-1', { code: '1234' } as any)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws AUTH_008 when the PIN is wrong', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      usersRepo.findById.mockResolvedValue({ code_hash: await bcrypt.hash('1234', 10) });

      await expect(service.deleteAccount('user-1', { code: '0000' } as any)).rejects.toMatchObject({
        code: 'AUTH_008',
      });
      expect(usersRepo.anonymizeAndDeactivate).not.toHaveBeenCalled();
    });

    it('anonymizes the account and the contact person, and audit-logs the deletion', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ id: 'op-1' });
      usersRepo.findById.mockResolvedValue({ code_hash: await bcrypt.hash('1234', 10) });

      const result = await service.deleteAccount('user-1', { code: '1234' } as any, '127.0.0.1');

      expect(usersRepo.anonymizeAndDeactivate).toHaveBeenCalledWith('user-1');
      expect(organisationProfilesRepo.anonymizeContactPerson).toHaveBeenCalledWith('op-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'account_deleted', entityType: 'organisation_profiles', entityId: 'op-1' }),
      );
      expect(result).toEqual({ message: 'Account deleted' });
    });
  });

  describe('updateFcmToken', () => {
    it('stores the token via usersRepo', async () => {
      const result = await service.updateFcmToken('user-1', { token: 'fcm-abc' } as any);
      expect(usersRepo.updateFcmToken).toHaveBeenCalledWith('user-1', 'fcm-abc');
      expect(result).toEqual({ message: 'FCM token updated' });
    });
  });
});
