import { TicketsService } from './tickets.service';

describe('TicketsService', () => {
  let service: TicketsService;
  let ticketsRepo: any;
  let usersRepo: any;
  let auditService: any;

  const ticket = {
    id: 'ticket-1',
    user_id: 'user-1',
    type: 'forgot_pin' as const,
    status: 'open' as const,
    phone: '+919876543210',
    notes: null,
    created_at: new Date('2026-01-01T00:00:00Z'),
    resolved_at: null,
    resolved_by: null,
  };

  beforeEach(() => {
    ticketsRepo = {
      create: jest.fn().mockResolvedValue(ticket),
      findOpenByUserAndType: jest.fn().mockResolvedValue(null),
      findById: jest.fn(),
      resolve: jest.fn(),
      list: jest.fn(),
    };
    usersRepo = { findByPhoneAnyRole: jest.fn() };
    auditService = { log: jest.fn() };
    service = new TicketsService(ticketsRepo, usersRepo, auditService);
  });

  describe('createForgotPinTicket', () => {
    it('throws AUTH_002 when no account exists for this phone', async () => {
      usersRepo.findByPhoneAnyRole.mockResolvedValue(null);
      await expect(
        service.createForgotPinTicket({ phone: '+919876543210' } as any, null),
      ).rejects.toMatchObject({ code: 'AUTH_002' });
      expect(ticketsRepo.create).not.toHaveBeenCalled();
    });

    it('creates a ticket and audit-logs it against the resolved account', async () => {
      usersRepo.findByPhoneAnyRole.mockResolvedValue({ id: 'user-1', role: 'caregiver' });
      const result = await service.createForgotPinTicket({ phone: '+919876543210' } as any, '127.0.0.1');

      expect(ticketsRepo.create).toHaveBeenCalledWith('user-1', 'forgot_pin', '+919876543210');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'support_ticket_created',
          entityType: 'support_tickets',
          entityId: 'ticket-1',
        }),
      );
      expect(result.message).toContain('support ticket has been created');
    });

    it('reuses an existing open ticket instead of creating a duplicate', async () => {
      usersRepo.findByPhoneAnyRole.mockResolvedValue({ id: 'user-1', role: 'caregiver' });
      ticketsRepo.findOpenByUserAndType.mockResolvedValue(ticket);

      const result = await service.createForgotPinTicket({ phone: '+919876543210' } as any, null);

      expect(ticketsRepo.create).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
      expect(result.message).toContain('already open');
    });
  });

  describe('list', () => {
    it('paginates and shapes meta correctly', async () => {
      ticketsRepo.list.mockResolvedValue({ items: [ticket], total: 25 });
      const result = await service.list({ page: 2, limit: 10 } as any);
      expect(ticketsRepo.list).toHaveBeenCalledWith({ status: undefined }, { page: 2, limit: 10 });
      expect(result.data).toEqual([ticket]);
      expect(result.meta).toEqual({ page: 2, limit: 10, total: 25, totalPages: 3 });
    });

    it('passes the status filter through', async () => {
      ticketsRepo.list.mockResolvedValue({ items: [], total: 0 });
      await service.list({ page: 1, limit: 20, status: 'open' } as any);
      expect(ticketsRepo.list).toHaveBeenCalledWith({ status: 'open' }, { page: 1, limit: 20 });
    });
  });

  describe('resolve', () => {
    it('throws GEN_002 when the ticket does not exist', async () => {
      ticketsRepo.findById.mockResolvedValue(null);
      await expect(service.resolve('ticket-1', 'admin-1', undefined, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws TICKET_001 when the ticket is already resolved', async () => {
      ticketsRepo.findById.mockResolvedValue({ ...ticket, status: 'resolved' });
      ticketsRepo.resolve.mockResolvedValue(null);
      await expect(service.resolve('ticket-1', 'admin-1', undefined, null)).rejects.toMatchObject({
        code: 'TICKET_001',
      });
    });

    it('resolves the ticket and audit-logs it against the requester', async () => {
      ticketsRepo.findById.mockResolvedValue(ticket);
      ticketsRepo.resolve.mockResolvedValue({ ...ticket, status: 'resolved' });

      const result = await service.resolve('ticket-1', 'admin-1', 'Reset via phone call', '127.0.0.1');

      expect(ticketsRepo.resolve).toHaveBeenCalledWith('ticket-1', 'admin-1', 'Reset via phone call');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'user-1',
          action: 'support_ticket_resolved',
          entityType: 'support_tickets',
          entityId: 'ticket-1',
        }),
      );
      expect(result).toEqual({ message: 'Ticket resolved' });
    });
  });
});
