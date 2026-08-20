import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AdminOrganisationsRepository } from '../database/repositories/admin-organisations.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { BlockIndividualDto } from './dto/block-individual.dto';
import { ListOrganisationsQueryDto } from './dto/list-organisations-query.dto';
import { AdminEditOrganisationDto } from './dto/admin-edit-organisation.dto';

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

  /** Admin override — full_name (the contact person's name) is kept in
   *  sync across both users.full_name (what the admin list/detail reads)
   *  and organisation_profiles.contact_person_name (what the org's own
   *  GET /organisation/me reads) since the two columns are otherwise
   *  independent copies set together only at registration. Audit-logs
   *  only the fields that actually changed. */
  async editProfile(
    targetUserId: string,
    adminId: string,
    dto: AdminEditOrganisationDto,
    ipAddress: string | null,
  ) {
    const organisation = await this.organisationsRepo.findDetailByUserId(targetUserId);
    if (!organisation) throw new AppException('GEN_002');

    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};
    const trackedFields = ['full_name', 'organisation_name', 'organisation_type', 'city', 'area'] as const;
    const organisationRecord = organisation as unknown as Record<string, unknown>;
    for (const field of trackedFields) {
      const nextValue = dto[field];
      if (nextValue === undefined) continue;
      if (organisationRecord[field] !== nextValue) {
        before[field] = organisationRecord[field];
        after[field] = nextValue;
      }
    }

    if (dto.full_name !== undefined) {
      await this.usersRepo.updateFullName(targetUserId, dto.full_name);
    }
    await this.organisationsRepo.adminUpdate(targetUserId, {
      organisation_name: dto.organisation_name,
      contact_person_name: dto.full_name,
      organisation_type: dto.organisation_type,
      city: dto.city,
      area: dto.area,
    });

    if (Object.keys(after).length > 0) {
      await this.auditService.log({
        userId: adminId,
        targetUserId,
        action: AuditAction.ADMIN_EDIT_PROFILE,
        entityType: 'organisation_profiles',
        entityId: targetUserId,
        beforeValue: before,
        afterValue: after,
        ipAddress,
      });
    }

    return { message: 'Profile updated' };
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
