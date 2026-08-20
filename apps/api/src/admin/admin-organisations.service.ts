import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AdminOrganisationsRepository } from '../database/repositories/admin-organisations.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { BlockIndividualDto } from './dto/block-individual.dto';
import { ListOrganisationsQueryDto } from './dto/list-organisations-query.dto';

/** Mirrors AdminIndividualsService exactly — reuses BlockIndividualDto/
 *  UnblockIndividualDto (level: 'job_posting' | 'full', role-agnostic). */
@Injectable()
export class AdminOrganisationsService {
  constructor(
    private readonly organisationsRepo: AdminOrganisationsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
  ) {}

  async listOrganisations(query: ListOrganisationsQueryDto) {
    const { items, total } = await this.organisationsRepo.listOrganisations(
      {
        search: query.search,
        blockStatus: query.block_status,
        organisationType: query.organisation_type,
        city: query.city,
      },
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

  async getOrganisationDetail(userId: string) {
    const organisation = await this.organisationsRepo.findDetailByUserId(userId);
    if (!organisation) throw new AppException('GEN_002');
    return organisation;
  }

  async block(targetUserId: string, dto: BlockIndividualDto, adminId: string, ipAddress: string | null) {
    const organisation = await this.organisationsRepo.findDetailByUserId(targetUserId);
    if (!organisation) throw new AppException('GEN_002');

    if (dto.level === 'full') {
      await this.usersRepo.setActive(targetUserId, false);
      await this.organisationsRepo.setBlockReason(targetUserId, dto.reason);
    } else {
      await this.organisationsRepo.setJobPostingBlocked(targetUserId, true, dto.reason);
    }

    await this.auditService.log({
      userId: adminId,
      targetUserId,
      action: AuditAction.STATUS_CHANGED,
      entityType: 'organisation_profiles',
      entityId: targetUserId,
      beforeValue: { level: dto.level, blocked: false },
      afterValue: { level: dto.level, blocked: true, reason: dto.reason },
      ipAddress,
    });

    return { message: 'Organisation blocked' };
  }

  async unblock(targetUserId: string, level: 'job_posting' | 'full', adminId: string, ipAddress: string | null) {
    const organisation = await this.organisationsRepo.findDetailByUserId(targetUserId);
    if (!organisation) throw new AppException('GEN_002');

    if (level === 'full') {
      await this.usersRepo.setActive(targetUserId, true);
      await this.organisationsRepo.setBlockReason(targetUserId, null);
    } else {
      await this.organisationsRepo.setJobPostingBlocked(targetUserId, false, null);
    }

    await this.auditService.log({
      userId: adminId,
      targetUserId,
      action: AuditAction.STATUS_CHANGED,
      entityType: 'organisation_profiles',
      entityId: targetUserId,
      beforeValue: { level, blocked: true },
      afterValue: { level, blocked: false },
      ipAddress,
    });

    return { message: 'Organisation unblocked' };
  }
}
