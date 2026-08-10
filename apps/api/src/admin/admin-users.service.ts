import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { CreateAdminDto } from './dto/create-admin.dto';
import { UpdateAdminDto } from './dto/update-admin.dto';
import { UpdateAdminRoleDto } from './dto/update-admin-role.dto';

@Injectable()
export class AdminUsersService {
  constructor(
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
  ) {}

  async listAdmins() {
    const admins = await this.usersRepo.listAdmins();
    return admins.map((admin) => ({
      user_id: admin.id,
      email: admin.email,
      phone: admin.phone,
      full_name: admin.full_name,
      role: admin.role,
      is_active: admin.is_active,
      created_at: admin.created_at,
    }));
  }

  async createAdmin(dto: CreateAdminDto, currentUserId: string, ipAddress: string | null = null) {
    const [existingByEmail, existingByPhone] = await Promise.all([
      this.usersRepo.findByEmail(dto.email),
      this.usersRepo.findByPhone(dto.phone),
    ]);
    if (existingByEmail) throw new AppException('ADMIN_003');
    if (existingByPhone) throw new AppException('ADMIN_009');

    const passwordHash = await bcrypt.hash(dto.password, Config.BCRYPT_SALT_ROUNDS);
    const admin = await this.usersRepo.create({
      phone: dto.phone,
      full_name: dto.full_name,
      role: UserRole.ADMIN,
      email: dto.email,
      password_hash: passwordHash,
    });

    await this.auditService.log({
      userId: currentUserId,
      targetUserId: admin.id,
      action: AuditAction.ADMIN_CREATED,
      entityType: 'users',
      entityId: admin.id,
      afterValue: { full_name: dto.full_name, email: dto.email, phone: dto.phone, role: UserRole.ADMIN },
      ipAddress,
    });

    return { user_id: admin.id, email: admin.email, role: admin.role };
  }

  async updateAdmin(targetId: string, dto: UpdateAdminDto) {
    const target = await this.usersRepo.findById(targetId);
    if (!target || (target.role !== UserRole.ADMIN && target.role !== UserRole.SUPER_ADMIN)) {
      throw new AppException('ADMIN_004');
    }
    if (dto.phone) {
      const existing = await this.usersRepo.findByPhone(dto.phone);
      if (existing && existing.id !== targetId) throw new AppException('ADMIN_009');
    }

    const updated = await this.usersRepo.updateAdmin(targetId, dto);
    return {
      user_id: updated!.id,
      email: updated!.email,
      phone: updated!.phone,
      full_name: updated!.full_name,
      role: updated!.role,
      is_active: updated!.is_active,
    };
  }

  async deactivateAdmin(targetId: string, currentUserId: string, ipAddress: string | null = null) {
    const target = await this.usersRepo.findById(targetId);
    if (!target || (target.role !== UserRole.ADMIN && target.role !== UserRole.SUPER_ADMIN)) {
      throw new AppException('ADMIN_004');
    }
    if (targetId === currentUserId) throw new AppException('ADMIN_005');
    if (target.role === UserRole.SUPER_ADMIN) throw new AppException('ADMIN_006');

    await this.usersRepo.setActive(targetId, false);

    await this.auditService.log({
      userId: currentUserId,
      targetUserId: targetId,
      action: AuditAction.ADMIN_DEACTIVATED,
      entityType: 'users',
      entityId: targetId,
      beforeValue: { is_active: true },
      afterValue: { is_active: false },
      ipAddress,
    });

    return { message: 'Admin deactivated' };
  }

  async activateAdmin(targetId: string, currentUserId: string, ipAddress: string | null = null) {
    const target = await this.usersRepo.findById(targetId);
    if (!target || (target.role !== UserRole.ADMIN && target.role !== UserRole.SUPER_ADMIN)) {
      throw new AppException('ADMIN_004');
    }

    await this.usersRepo.setActive(targetId, true);

    await this.auditService.log({
      userId: currentUserId,
      targetUserId: targetId,
      action: AuditAction.ADMIN_ACTIVATED,
      entityType: 'users',
      entityId: targetId,
      beforeValue: { is_active: target.is_active },
      afterValue: { is_active: true },
      ipAddress,
    });

    return { message: 'Admin activated' };
  }

  async updateAdminRole(
    targetId: string,
    dto: UpdateAdminRoleDto,
    currentUserId: string,
    ipAddress: string | null = null,
  ) {
    const target = await this.usersRepo.findById(targetId);
    if (!target || (target.role !== UserRole.ADMIN && target.role !== UserRole.SUPER_ADMIN)) {
      throw new AppException('ADMIN_004');
    }
    if (targetId === currentUserId) throw new AppException('ADMIN_012');
    if (target.role === UserRole.SUPER_ADMIN && dto.role === UserRole.ADMIN) {
      const superAdminCount = await this.usersRepo.countSuperAdmins();
      if (superAdminCount <= 1) throw new AppException('ADMIN_013');
    }

    await this.usersRepo.updateRole(targetId, dto.role);

    await this.auditService.log({
      userId: currentUserId,
      targetUserId: targetId,
      action: AuditAction.ADMIN_ROLE_CHANGED,
      entityType: 'users',
      entityId: targetId,
      beforeValue: { role: target.role },
      afterValue: { role: dto.role },
      ipAddress,
    });

    return { user_id: targetId, role: dto.role };
  }
}
