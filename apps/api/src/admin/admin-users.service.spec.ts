import { AdminUsersService } from './admin-users.service';
import { UserRole } from '@vitacare/shared-constants';

describe('AdminUsersService', () => {
  let service: AdminUsersService;
  let usersRepo: any;
  let auditService: any;

  const adminUser = {
    id: 'admin-1',
    email: 'admin1@vitacasahealth.in',
    phone: '+919999999999',
    full_name: 'Admin One',
    role: UserRole.ADMIN,
    is_active: true,
    created_at: new Date(),
  };

  beforeEach(() => {
    usersRepo = {
      listAdmins: jest.fn(),
      findByEmail: jest.fn(),
      findByPhoneAndRoles: jest.fn(),
      findById: jest.fn(),
      create: jest.fn(),
      updateAdmin: jest.fn(),
      setActive: jest.fn(),
      updateRole: jest.fn(),
      countSuperAdmins: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new AdminUsersService(usersRepo, auditService);
  });

  describe('listAdmins', () => {
    it('maps user records to the admin list shape', async () => {
      usersRepo.listAdmins.mockResolvedValue([adminUser]);
      const result = await service.listAdmins();
      expect(result).toEqual([
        {
          user_id: 'admin-1',
          email: adminUser.email,
          phone: adminUser.phone,
          full_name: adminUser.full_name,
          role: 'admin',
          is_active: true,
          created_at: adminUser.created_at,
        },
      ]);
    });
  });

  describe('createAdmin', () => {
    const dto = {
      email: 'new@vitacasahealth.in',
      phone: '+919999900001',
      full_name: 'New Admin',
      password: 'securepass1',
    };

    it('throws ADMIN_003 when the email is already taken', async () => {
      usersRepo.findByEmail.mockResolvedValue(adminUser);
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      await expect(service.createAdmin(dto as any, 'admin-1')).rejects.toMatchObject({
        code: 'ADMIN_003',
      });
    });

    it('throws ADMIN_009 when the phone is already taken', async () => {
      usersRepo.findByEmail.mockResolvedValue(null);
      usersRepo.findByPhoneAndRoles.mockResolvedValue(adminUser);
      await expect(service.createAdmin(dto as any, 'admin-1')).rejects.toMatchObject({
        code: 'ADMIN_009',
      });
    });

    it('creates the admin with role=admin and a hashed password', async () => {
      usersRepo.findByEmail.mockResolvedValue(null);
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);
      usersRepo.create.mockResolvedValue({ id: 'new-1', email: dto.email, role: 'admin' });

      const result = await service.createAdmin(dto as any, 'admin-1');

      expect(usersRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ role: UserRole.ADMIN, email: dto.email, phone: dto.phone }),
      );
      const createCall = usersRepo.create.mock.calls[0][0];
      expect(createCall.password_hash).not.toBe(dto.password);
      expect(result).toEqual({ user_id: 'new-1', email: dto.email, role: 'admin' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', targetUserId: 'new-1', action: 'admin_created' }),
      );
    });
  });

  describe('updateAdmin', () => {
    it('throws ADMIN_004 when the target is not an admin/super_admin', async () => {
      usersRepo.findById.mockResolvedValue({ ...adminUser, role: UserRole.CAREGIVER });
      await expect(service.updateAdmin('someone', {} as any)).rejects.toMatchObject({
        code: 'ADMIN_004',
      });
    });

    it('throws ADMIN_009 when the new phone belongs to a different user', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ ...adminUser, id: 'someone-else' });
      await expect(
        service.updateAdmin('admin-1', { phone: '+919999900002' } as any),
      ).rejects.toMatchObject({ code: 'ADMIN_009' });
    });

    it('allows keeping the same phone on the same admin', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      usersRepo.findByPhoneAndRoles.mockResolvedValue(adminUser);
      usersRepo.updateAdmin.mockResolvedValue(adminUser);
      await expect(
        service.updateAdmin('admin-1', { phone: adminUser.phone } as any),
      ).resolves.toBeDefined();
    });
  });

  describe('deactivateAdmin', () => {
    it('throws ADMIN_004 when the target does not exist', async () => {
      usersRepo.findById.mockResolvedValue(null);
      await expect(service.deactivateAdmin('missing', 'admin-1')).rejects.toMatchObject({
        code: 'ADMIN_004',
      });
    });

    it('throws ADMIN_005 on self-deactivation', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      await expect(service.deactivateAdmin('admin-1', 'admin-1')).rejects.toMatchObject({
        code: 'ADMIN_005',
      });
    });

    it('throws ADMIN_006 when target is a super_admin', async () => {
      usersRepo.findById.mockResolvedValue({ ...adminUser, role: UserRole.SUPER_ADMIN });
      await expect(service.deactivateAdmin('admin-1', 'other-admin')).rejects.toMatchObject({
        code: 'ADMIN_006',
      });
    });

    it('deactivates a regular admin', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      const result = await service.deactivateAdmin('admin-1', 'other-admin');
      expect(usersRepo.setActive).toHaveBeenCalledWith('admin-1', false);
      expect(result).toEqual({ message: 'Admin deactivated' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'other-admin',
          targetUserId: 'admin-1',
          action: 'admin_deactivated',
        }),
      );
    });
  });

  describe('activateAdmin', () => {
    it('throws ADMIN_004 when the target does not exist', async () => {
      usersRepo.findById.mockResolvedValue(null);
      await expect(service.activateAdmin('missing', 'other-admin')).rejects.toMatchObject({
        code: 'ADMIN_004',
      });
    });

    it('reactivates a deactivated admin', async () => {
      usersRepo.findById.mockResolvedValue({ ...adminUser, is_active: false });
      const result = await service.activateAdmin('admin-1', 'other-admin');
      expect(usersRepo.setActive).toHaveBeenCalledWith('admin-1', true);
      expect(result).toEqual({ message: 'Admin activated' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'other-admin',
          targetUserId: 'admin-1',
          action: 'admin_activated',
          beforeValue: { is_active: false },
          afterValue: { is_active: true },
        }),
      );
    });

    it('is idempotent when the admin is already active', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      const result = await service.activateAdmin('admin-1', 'other-admin');
      expect(usersRepo.setActive).toHaveBeenCalledWith('admin-1', true);
      expect(result).toEqual({ message: 'Admin activated' });
    });
  });

  describe('updateAdminRole', () => {
    it('throws ADMIN_004 when the target is not an admin/super_admin', async () => {
      usersRepo.findById.mockResolvedValue({ ...adminUser, role: UserRole.CAREGIVER });
      await expect(
        service.updateAdminRole('someone', { role: UserRole.SUPER_ADMIN } as any, 'other-admin'),
      ).rejects.toMatchObject({ code: 'ADMIN_004' });
    });

    it('throws ADMIN_012 on self-role-change', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      await expect(
        service.updateAdminRole('admin-1', { role: UserRole.SUPER_ADMIN } as any, 'admin-1'),
      ).rejects.toMatchObject({ code: 'ADMIN_012' });
    });

    it('promotes an admin to super_admin', async () => {
      usersRepo.findById.mockResolvedValue(adminUser);
      const result = await service.updateAdminRole(
        'admin-1',
        { role: UserRole.SUPER_ADMIN } as any,
        'other-admin',
      );
      expect(usersRepo.updateRole).toHaveBeenCalledWith('admin-1', UserRole.SUPER_ADMIN);
      expect(result).toEqual({ user_id: 'admin-1', role: UserRole.SUPER_ADMIN });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'other-admin',
          targetUserId: 'admin-1',
          action: 'admin_role_changed',
          beforeValue: { role: UserRole.ADMIN },
          afterValue: { role: UserRole.SUPER_ADMIN },
        }),
      );
    });

    it('throws ADMIN_013 when demoting the last remaining super_admin', async () => {
      usersRepo.findById.mockResolvedValue({ ...adminUser, role: UserRole.SUPER_ADMIN });
      usersRepo.countSuperAdmins.mockResolvedValue(1);
      await expect(
        service.updateAdminRole('admin-1', { role: UserRole.ADMIN } as any, 'other-admin'),
      ).rejects.toMatchObject({ code: 'ADMIN_013' });
      expect(usersRepo.updateRole).not.toHaveBeenCalled();
    });

    it('allows demoting a super_admin when another super_admin remains', async () => {
      usersRepo.findById.mockResolvedValue({ ...adminUser, role: UserRole.SUPER_ADMIN });
      usersRepo.countSuperAdmins.mockResolvedValue(2);
      const result = await service.updateAdminRole(
        'admin-1',
        { role: UserRole.ADMIN } as any,
        'other-admin',
      );
      expect(usersRepo.updateRole).toHaveBeenCalledWith('admin-1', UserRole.ADMIN);
      expect(result).toEqual({ user_id: 'admin-1', role: UserRole.ADMIN });
    });
  });
});
