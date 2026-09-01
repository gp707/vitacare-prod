import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { DutyRequirementsRepository } from '../database/repositories/duty-requirements.repository';
import { UpdateDutyRequirementsDto } from './dto/update-duty-requirements.dto';

@Injectable()
export class DutyRequirementsService {
  constructor(
    private readonly dutyRequirementsRepo: DutyRequirementsRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — nursenow-app's Individual Post/Edit Requirement forms fetch
   *  this once per "Hours Care Needed" info-button tap and show only the
   *  list for whichever shift is currently selected on the form. */
  get() {
    return this.dutyRequirementsRepo.find();
  }

  adminGet() {
    return this.dutyRequirementsRepo.findWithUpdater();
  }

  async adminUpdate(adminId: string, dto: UpdateDutyRequirementsDto, ipAddress: string | null) {
    this.validateLists(dto);

    const existing = await this.dutyRequirementsRepo.find();
    const updated = await this.dutyRequirementsRepo.update(dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.DUTY_REQUIREMENTS_UPDATED,
      entityType: 'duty_requirements',
      beforeValue: {
        live_in: existing.live_in,
        day_duty: existing.day_duty,
        night_duty: existing.night_duty,
      },
      afterValue: {
        live_in: dto.live_in,
        day_duty: dto.day_duty,
        night_duty: dto.night_duty,
      },
      ipAddress,
    });

    return updated;
  }

  /** class-validator's `@IsString({each: true})` accepts blank strings, so
   *  the "no empty bullets" rule is enforced here instead, with its own
   *  dedicated error code. */
  private validateLists(dto: UpdateDutyRequirementsDto) {
    const lists = [dto.live_in, dto.day_duty, dto.night_duty];
    const isValid = lists.every(
      (list) => Array.isArray(list) && list.length > 0 && list.every((bullet) => bullet.trim().length > 0),
    );
    if (!isValid) throw new AppException('DUTY_001');
  }
}
