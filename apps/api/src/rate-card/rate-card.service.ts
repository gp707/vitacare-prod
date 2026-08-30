import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { AuditService } from '../audit/audit.service';
import { RateCardRepository } from '../database/repositories/rate-card.repository';
import { UpdateRateCardDto } from './dto/update-rate-card.dto';

@Injectable()
export class RateCardService {
  constructor(
    private readonly rateCardRepo: RateCardRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — every caregiver-app and nursenow-app (Individual only,
   *  never Organisation) screen fetches this once and shows it behind a
   *  persistent app-bar icon. */
  get() {
    return this.rateCardRepo.find();
  }

  adminGet() {
    return this.rateCardRepo.findWithUpdater();
  }

  async adminUpdate(adminId: string, dto: UpdateRateCardDto, ipAddress: string | null) {
    this.validateCellsShape(dto.cells);

    const existing = await this.rateCardRepo.find();
    const updated = await this.rateCardRepo.update(dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.RATE_CARD_UPDATED,
      entityType: 'rate_card',
      beforeValue: { title: existing.title, cells: existing.cells },
      afterValue: { title: dto.title, cells: dto.cells },
      ipAddress,
    });

    return updated;
  }

  /** class-validator has no clean decorator for a nested string[][] shape
   *  (see UpdateRateCardDto), so the actual 3x3-of-strings check happens
   *  here instead, with its own dedicated error code. */
  private validateCellsShape(cells: string[][]) {
    const isValid =
      Array.isArray(cells) &&
      cells.length === 3 &&
      cells.every((row) => Array.isArray(row) && row.length === 3 && row.every((cell) => typeof cell === 'string'));
    if (!isValid) throw new AppException('RATE_001');
  }
}
