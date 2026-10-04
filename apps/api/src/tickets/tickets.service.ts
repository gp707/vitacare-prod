import { Injectable } from '@nestjs/common';
import { AuditAction, TicketType } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { TicketsRepository } from '../database/repositories/tickets.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { AuditService } from '../audit/audit.service';
import { ForgotPinDto } from './dto/forgot-pin.dto';
import { ListTicketsQueryDto } from './dto/list-tickets-query.dto';

@Injectable()
export class TicketsService {
  constructor(
    private readonly ticketsRepo: TicketsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
  ) {}

  /** No auth required — this runs before the user can log in at all. Phone
   *  is looked up across every role (caregiver/individual/organisation,
   *  phone is globally unique at registration time — see CLAUDE.md), same
   *  AUTH_002 the login screens already surface for "no account with this
   *  phone number" if nothing matches, so this never confirms or denies an
   *  account's existence any more precisely than login already does. If
   *  the account already has an open forgot_pin ticket, that one is
   *  reused instead of creating a duplicate. */
  async createForgotPinTicket(dto: ForgotPinDto, ipAddress: string | null) {
    const user = await this.usersRepo.findByPhoneAnyRole(dto.phone);
    if (!user) throw new AppException('AUTH_002');

    const existing = await this.ticketsRepo.findOpenByUserAndType(user.id, TicketType.FORGOT_PIN);
    if (existing) {
      return { message: 'A support ticket is already open for this account. Our team will contact you.' };
    }

    const ticket = await this.ticketsRepo.create(user.id, TicketType.FORGOT_PIN, dto.phone);

    await this.auditService.log({
      userId: user.id,
      action: AuditAction.SUPPORT_TICKET_CREATED,
      entityType: 'support_tickets',
      entityId: ticket.id,
      afterValue: { type: ticket.type, phone: ticket.phone },
      ipAddress,
    });

    return { message: 'A support ticket has been created. Our team will contact you to verify your identity and reset your PIN.' };
  }

  async list(query: ListTicketsQueryDto) {
    const { items, total } = await this.ticketsRepo.list(
      { status: query.status },
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

  async resolve(id: string, adminId: string, notes: string | undefined, ipAddress: string | null) {
    const existing = await this.ticketsRepo.findById(id);
    if (!existing) throw new AppException('GEN_002');

    const resolved = await this.ticketsRepo.resolve(id, adminId, notes ?? null);
    if (!resolved) throw new AppException('TICKET_001');

    await this.auditService.log({
      userId: adminId,
      targetUserId: existing.user_id,
      action: AuditAction.SUPPORT_TICKET_RESOLVED,
      entityType: 'support_tickets',
      entityId: id,
      afterValue: { notes: notes ?? null },
      ipAddress,
    });

    return { message: 'Ticket resolved' };
  }
}
