import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuditAction, Config, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AdminIndividualsRepository } from '../database/repositories/admin-individuals.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { IndividualAdminNotesRepository } from '../database/repositories/individual-admin-notes.repository';
import { AuditService } from '../audit/audit.service';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { BlockIndividualDto } from './dto/block-individual.dto';
import { ListIndividualsQueryDto } from './dto/list-individuals-query.dto';
import { AdminEditIndividualDto } from './dto/admin-edit-individual.dto';
import { UpdateCodeDto } from '../caregiver/dto/update-code.dto';

@Injectable()
export class AdminIndividualsService {
  constructor(
    private readonly individualsRepo: AdminIndividualsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly notesRepo: IndividualAdminNotesRepository,
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
    const notes = await this.notesRepo.findByUserId(userId);
    return { ...individual, notes: notes?.notes ?? null };
  }

  /** Admin-only personal/internal note about this patient/family account —
   *  never exposed to the individual's own self-view. */
  async upsertNotes(targetUserId: string, adminId: string, notes: string | null, ipAddress: string | null) {
    const individual = await this.individualsRepo.findDetailByUserId(targetUserId);
    if (!individual) throw new AppException('GEN_002');

    const previous = await this.notesRepo.findByUserId(targetUserId);
    await this.notesRepo.upsert(targetUserId, adminId, notes);

    await this.auditService.log({
      userId: adminId,
      targetUserId,
      action: AuditAction.ADMIN_NOTE_ADDED,
      entityType: 'individual_admin_notes',
      entityId: targetUserId,
      beforeValue: { notes: previous?.notes ?? null },
      afterValue: { notes },
      ipAddress,
    });

    return { message: 'Notes saved' };
  }

  /** Admin-initiated PIN reset — bypasses the self-service old-value check
   *  entirely (there isn't one — see caregiver/organisation's own
   *  updateCode), same hashing/storage as a self-service change. */
  async resetCode(targetUserId: string, adminId: string, dto: UpdateCodeDto, ipAddress: string | null) {
    const individual = await this.individualsRepo.findDetailByUserId(targetUserId);
    if (!individual) throw new AppException('GEN_002');

    const codeHash = await bcrypt.hash(dto.code, Config.BCRYPT_SALT_ROUNDS);
    await this.usersRepo.updateCodeHash(targetUserId, codeHash);

    await this.auditService.log({
      userId: adminId,
      targetUserId,
      action: AuditAction.ADMIN_CODE_RESET,
      entityType: 'individual_profiles',
      entityId: targetUserId,
      ipAddress,
    });

    return { message: 'Login code reset' };
  }

  /** Admin override — an individual_profiles row has no profile depth
   *  beyond the block levers, so this only ever touches users.full_name/
   *  phone. Audit-logs only the fields that actually changed. Unlike the
   *  individual's own self-service `updatePhone`, this never triggers any
   *  re-review (individual accounts have no verification pipeline anyway)
   *  — it's a plain in-place update of the same users row, so the
   *  profile/requirements posted/applications are all untouched (they're
   *  keyed on user_id, never on phone). */
  async editProfile(
    targetUserId: string,
    adminId: string,
    dto: AdminEditIndividualDto,
    ipAddress: string | null,
  ) {
    const individual = await this.individualsRepo.findDetailByUserId(targetUserId);
    if (!individual) throw new AppException('GEN_002');

    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};

    if (dto.full_name !== undefined && dto.full_name !== individual.full_name) {
      await this.usersRepo.updateFullName(targetUserId, dto.full_name);
      before.full_name = individual.full_name;
      after.full_name = dto.full_name;
    }

    if (dto.phone !== undefined && dto.phone !== individual.phone) {
      const existing = await this.usersRepo.findByPhoneAndRoles(dto.phone, [
        UserRole.INDIVIDUAL,
        UserRole.ORGANISATION,
      ]);
      if (existing) throw new AppException('AUTH_001');
      await this.usersRepo.updatePhone(targetUserId, dto.phone);
      before.phone = individual.phone;
      after.phone = dto.phone;
    }

    if (Object.keys(after).length > 0) {
      await this.auditService.log({
        userId: adminId,
        targetUserId,
        action: AuditAction.ADMIN_EDIT_PROFILE,
        entityType: 'individual_profiles',
        entityId: targetUserId,
        beforeValue: before,
        afterValue: after,
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
