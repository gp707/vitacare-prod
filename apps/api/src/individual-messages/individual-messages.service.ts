import { Injectable, NotFoundException } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { AuditService } from '../audit/audit.service';
import { IndividualMessagesRepository } from '../database/repositories/individual-messages.repository';
import { CreateIndividualMessageDto } from './dto/create-individual-message.dto';
import { UpdateIndividualMessageDto } from './dto/update-individual-message.dto';

@Injectable()
export class IndividualMessagesService {
  constructor(
    private readonly individualMessagesRepo: IndividualMessagesRepository,
    private readonly auditService: AuditService,
  ) {}

  /** Public — nursenow-app's Messages tab fetches this once per screen
   *  load, in parallel with its own GET /individual/requirements call,
   *  and evaluates which messages currently apply client-side. */
  get() {
    return this.individualMessagesRepo.findEnabled();
  }

  adminList() {
    return this.individualMessagesRepo.findAll();
  }

  async adminCreate(adminId: string, dto: CreateIndividualMessageDto, ipAddress: string | null) {
    const created = await this.individualMessagesRepo.create(
      { ...dto, enabled: dto.enabled ?? true },
      adminId,
    );

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.INDIVIDUAL_MESSAGE_CREATED,
      entityType: 'individual_messages',
      entityId: created.id,
      afterValue: { ...created },
      ipAddress,
    });

    return created;
  }

  async adminUpdate(
    adminId: string,
    id: string,
    dto: UpdateIndividualMessageDto,
    ipAddress: string | null,
  ) {
    const existing = await this.individualMessagesRepo.findById(id);
    if (!existing) throw new NotFoundException();

    const updated = await this.individualMessagesRepo.update(id, dto, adminId);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.INDIVIDUAL_MESSAGE_UPDATED,
      entityType: 'individual_messages',
      entityId: id,
      beforeValue: { ...existing },
      afterValue: { ...updated },
      ipAddress,
    });

    return updated;
  }

  async adminDelete(adminId: string, id: string, ipAddress: string | null) {
    const existing = await this.individualMessagesRepo.findById(id);
    if (!existing) throw new NotFoundException();

    await this.individualMessagesRepo.delete(id);

    await this.auditService.log({
      userId: adminId,
      action: AuditAction.INDIVIDUAL_MESSAGE_DELETED,
      entityType: 'individual_messages',
      entityId: id,
      beforeValue: { ...existing },
      ipAddress,
    });

    return { message: 'Message deleted' };
  }
}
