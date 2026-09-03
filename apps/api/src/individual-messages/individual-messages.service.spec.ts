import { NotFoundException } from '@nestjs/common';
import { IndividualMessagesService } from './individual-messages.service';

describe('IndividualMessagesService', () => {
  let service: IndividualMessagesService;
  let individualMessagesRepo: any;
  let auditService: any;

  const existingRow = {
    id: 'msg-1',
    event: 'requirement_live',
    icon: 'edit_note',
    message: 'You can edit this job and change salary.',
    display_order: 10,
    enabled: true,
    created_by: 'admin-1',
    updated_by: 'admin-1',
    created_at: new Date(),
    updated_at: new Date(),
  };

  beforeEach(() => {
    individualMessagesRepo = {
      findEnabled: jest.fn(),
      findAll: jest.fn(),
      findById: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new IndividualMessagesService(individualMessagesRepo, auditService);
  });

  describe('get', () => {
    it('returns only enabled rows from the repository', async () => {
      individualMessagesRepo.findEnabled.mockResolvedValue([existingRow]);
      const result = await service.get();
      expect(result).toEqual([existingRow]);
      expect(individualMessagesRepo.findEnabled).toHaveBeenCalled();
    });
  });

  describe('adminList', () => {
    it('returns every row regardless of enabled state', async () => {
      individualMessagesRepo.findAll.mockResolvedValue([existingRow]);
      const result = await service.adminList();
      expect(result).toEqual([existingRow]);
    });
  });

  describe('adminCreate', () => {
    it('creates the row, defaults enabled to true when omitted, and audit-logs it', async () => {
      const dto = {
        event: 'requirement_live',
        icon: 'edit_note',
        message: 'New tip',
        display_order: 50,
      };
      individualMessagesRepo.create.mockResolvedValue({ ...existingRow, ...dto, id: 'msg-2' });

      const result = await service.adminCreate('admin-1', dto as any, '127.0.0.1');

      expect(individualMessagesRepo.create).toHaveBeenCalledWith({ ...dto, enabled: true }, 'admin-1');
      expect(result.id).toBe('msg-2');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'individual_message_created',
          entityType: 'individual_messages',
          entityId: 'msg-2',
          ipAddress: '127.0.0.1',
        }),
      );
    });

    it('respects an explicit enabled: false', async () => {
      const dto = { event: 'welcome', icon: 'waving_hand', message: 'Hi', display_order: 10, enabled: false };
      individualMessagesRepo.create.mockResolvedValue({ ...existingRow, ...dto });

      await service.adminCreate('admin-1', dto as any, null);

      expect(individualMessagesRepo.create).toHaveBeenCalledWith(dto, 'admin-1');
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs before/after values', async () => {
      individualMessagesRepo.findById.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, message: 'Updated tip' };
      individualMessagesRepo.update.mockResolvedValue(updatedRow);

      const dto = { message: 'Updated tip' };
      const result = await service.adminUpdate('admin-1', 'msg-1', dto as any, '127.0.0.1');

      expect(result).toEqual(updatedRow);
      expect(individualMessagesRepo.update).toHaveBeenCalledWith('msg-1', dto, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'individual_message_updated',
          entityType: 'individual_messages',
          entityId: 'msg-1',
          beforeValue: existingRow,
          afterValue: updatedRow,
        }),
      );
    });

    it('throws NotFoundException when the message does not exist', async () => {
      individualMessagesRepo.findById.mockResolvedValue(null);

      await expect(service.adminUpdate('admin-1', 'missing', {} as any, null)).rejects.toBeInstanceOf(
        NotFoundException,
      );
      expect(individualMessagesRepo.update).not.toHaveBeenCalled();
    });
  });

  describe('adminDelete', () => {
    it('deletes the row and audit-logs the before value', async () => {
      individualMessagesRepo.findById.mockResolvedValue(existingRow);

      const result = await service.adminDelete('admin-1', 'msg-1', '127.0.0.1');

      expect(individualMessagesRepo.delete).toHaveBeenCalledWith('msg-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'individual_message_deleted',
          entityType: 'individual_messages',
          entityId: 'msg-1',
          beforeValue: existingRow,
        }),
      );
      expect(result).toEqual({ message: 'Message deleted' });
    });

    it('throws NotFoundException when the message does not exist', async () => {
      individualMessagesRepo.findById.mockResolvedValue(null);

      await expect(service.adminDelete('admin-1', 'missing', null)).rejects.toBeInstanceOf(NotFoundException);
      expect(individualMessagesRepo.delete).not.toHaveBeenCalled();
    });
  });
});
