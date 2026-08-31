import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { ScopeOfWorkRepository } from '../database/repositories/scope-of-work.repository';
import { UpdateScopeOfWorkDto } from './dto/update-scope-of-work.dto';

@Injectable()
export class ScopeOfWorkService {
  constructor(
    private readonly scopeOfWorkRepo: ScopeOfWorkRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — caregiver-app fetches this once per job-card tap to render
   *  the bullet list for whichever tier that job's care_receiver derives
   *  to. Never shown on Organisation postings, which have no care_receiver
   *  to derive a tier from. */
  get() {
    return this.scopeOfWorkRepo.find();
  }

  adminGet() {
    return this.scopeOfWorkRepo.findWithUpdater();
  }

  async adminUpdate(adminId: string, dto: UpdateScopeOfWorkDto, ipAddress: string | null) {
    this.validateTiers(dto);

    const existing = await this.scopeOfWorkRepo.find();
    const updated = await this.scopeOfWorkRepo.update(dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.SCOPE_OF_WORK_UPDATED,
      entityType: 'scope_of_work',
      beforeValue: {
        companion_care: existing.companion_care,
        bedside_care: existing.bedside_care,
        critical_care: existing.critical_care,
      },
      afterValue: {
        companion_care: dto.companion_care,
        bedside_care: dto.bedside_care,
        critical_care: dto.critical_care,
      },
      ipAddress,
    });

    return updated;
  }

  /** class-validator's `@IsString({each: true})` accepts blank strings, so
   *  the "no empty bullets" rule is enforced here instead, with its own
   *  dedicated error code. */
  private validateTiers(dto: UpdateScopeOfWorkDto) {
    const tiers = [dto.companion_care, dto.bedside_care, dto.critical_care];
    const isValid = tiers.every(
      (tier) => Array.isArray(tier) && tier.length > 0 && tier.every((bullet) => bullet.trim().length > 0),
    );
    if (!isValid) throw new AppException('SCOPE_001');
  }
}
