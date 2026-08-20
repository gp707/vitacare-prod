import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AdminIndividualsRepository } from '../database/repositories/admin-individuals.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { BlockIndividualDto } from './dto/block-individual.dto';
import { ListIndividualsQueryDto } from './dto/list-individuals-query.dto';
import { AdminEditIndividualDto } from './dto/admin-edit-individual.dto';

@Injectable()
export class AdminIndividualsService {
  constructor(
    private readonly individualsRepo: AdminIndividualsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
  ) {}

  async listIndividuals(query: ListIndividualsQueryDto) {
    const { items, total } = await this.individualsRepo.listIndividuals(
      { search: query.search, blockStatus: query.block_status },
      { page: query.page, limit: query.limit },
    );
    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };
    return { data: items, meta };
  }

  async getIndividualDetail(userId: string) {
    const individual = await this.individualsRepo.findDetailByUserId(userId);
    if (!individual) throw new AppException('GEN_002');
    return individual;
  }

  /** Admin override — an individual_profiles row has no profile depth
   *  beyond the block levers, so this only ever touches users.full_name.
   *  Audit-logs only if the name actually changed. */
  async editProfile(
    targetUserId: string,
    adminId: string,
    dto: AdminEditIndividualDto,
    ipAddress: string | null,
  ) {
    const individual = await this.individualsRepo.findDetailByUserId(targetUserId);
    if (!individual) throw new AppException('GEN_002');

    if (dto.full_name !== undefined && dto.full_name !== individual.full_name) {
      await this.usersRepo.updateFullName(targetUserId, dto.full_name);
      await this.auditService.log({
        userId: adminId,
        targetUserId,
        action: AuditAction.ADMIN_EDIT_PROFILE,
        entityType: 'individual_profiles',
        entityId: targetUserId,
        beforeValue: { full_name: individual.full_name },
        afterValue: { full_name: dto.full_name },
        ipAddress,
      });
    }

    return { message: 'Profile updated' };
  }

  async block(
    targetUserId: string,
    dto: BlockIndividualDto,
    adminId: string,
    ipAddress: string | null,
  ) {
    const individual = await this.individualsRepo.findDetailByUserId(targetUserId);
    if (!individual) throw new AppException('GEN_002');

    if (dto.level === 'full') {
      await this.usersRepo.setActive(targetUserId, false);
      await this.individualsRepo.setBlockReason(targetUserId, dto.reason);
    } else {
      await this.individualsRepo.setJobPostingBlocked(targetUserId, true, dto.reason);
    }

    await this.auditService.log({
      userId: adminId,
      targetUserId,
      action: AuditAction.STATUS_CHANGED,
      entityType: 'individual_profiles',
      entityId: targetUserId,
      beforeValue: { level: dto.level, blocked: false },
      afterValue: { level: dto.level, blocked: true, reason: dto.reason },
      ipAddress,
    });

    return { message: 'Individual blocked' };
  }

  async unblock(targetUserId: string, level: 'job_posting' | 'full', adminId: string, ipAddress: string | null) {
    const individual = await this.individualsRepo.findDetailByUserId(targetUserId);
    if (!individual) throw new AppException('GEN_002');

    if (level === 'full') {
      await this.usersRepo.setActive(targetUserId, true);
      await this.individualsRepo.setBlockReason(targetUserId, null);
    } else {
      await this.individualsRepo.setJobPostingBlocked(targetUserId, false, null);
    }

    await this.auditService.log({
      userId: adminId,
      targetUserId,
      action: AuditAction.STATUS_CHANGED,
      entityType: 'individual_profiles',
      entityId: targetUserId,
      beforeValue: { level, blocked: true },
      afterValue: { level, blocked: false },
      ipAddress,
    });

    return { message: 'Individual unblocked' };
  }
}
