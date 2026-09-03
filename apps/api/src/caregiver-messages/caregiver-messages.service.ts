import { Injectable, NotFoundException } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AuditService } from '../audit/audit.service';
import { CaregiverMessagesRepository } from '../database/repositories/caregiver-messages.repository';
import { CreateCaregiverMessageDto } from './dto/create-caregiver-message.dto';
import { UpdateCaregiverMessageDto } from './dto/update-caregiver-message.dto';

@Injectable()
export class CaregiverMessagesService {
  constructor(
    private readonly caregiverMessagesRepo: CaregiverMessagesRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — caregiver-app's Messages bell fetches this once per screen
   *  load, in parallel with its own GET /caregiver/jobs and GET /caregiver/
   *  jobs/assigned calls, and evaluates which messages currently apply
   *  client-side. */
  get() {
    return this.caregiverMessagesRepo.findEnabled();
  }

  adminList() {
    return this.caregiverMessagesRepo.findAll();
  }

  async adminCreate(adminId: string, dto: CreateCaregiverMessageDto, ipAddress: string | null) {
    const created = await this.caregiverMessagesRepo.create(
      { ...dto, enabled: dto.enabled ?? true },
      adminId,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.CAREGIVER_MESSAGE_CREATED,
      entityType: 'caregiver_messages',
      entityId: created.id,
      afterValue: { ...created },
      ipAddress,
    });

    return created;
  }

  async adminUpdate(
    adminId: string,
    id: string,
    dto: UpdateCaregiverMessageDto,
    ipAddress: string | null,
  ) {
    const existing = await this.caregiverMessagesRepo.findById(id);
    if (!existing) throw new NotFoundException();

    const updated = await this.caregiverMessagesRepo.update(id, dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.CAREGIVER_MESSAGE_UPDATED,
      entityType: 'caregiver_messages',
      entityId: id,
      beforeValue: { ...existing },
      afterValue: { ...updated },
      ipAddress,
    });

    return updated;
  }

  async adminDelete(adminId: string, id: string, ipAddress: string | null) {
    const existing = await this.caregiverMessagesRepo.findById(id);
    if (!existing) throw new NotFoundException();

    await this.caregiverMessagesRepo.delete(id);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.CAREGIVER_MESSAGE_DELETED,
      entityType: 'caregiver_messages',
      entityId: id,
      beforeValue: { ...existing },
      ipAddress,
    });

    return { message: 'Message deleted' };
  }
}
