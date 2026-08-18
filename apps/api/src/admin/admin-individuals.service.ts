import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AdminIndividualsRepository } from '../database/repositories/admin-individuals.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { BlockIndividualDto } from './dto/block-individual.dto';

@Injectable()
export class AdminIndividualsService {
  constructor(
    private readonly individualsRepo: AdminIndividualsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
  ) {}

  async listIndividuals(page: number, limit: number) {
    const { items, total } = await this.individualsRepo.listIndividuals({ page, limit });
    const meta: PaginationMeta = { page, limit, total, totalPages: Math.max(1, Math.ceil(total / limit)) };
    return { data: items, meta };
  }

  async getIndividualDetail(userId: string) {
    const individual = await this.individualsRepo.findDetailByUserId(userId);
    if (!individual) throw new AppException('GEN_002');
    return individual;
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
