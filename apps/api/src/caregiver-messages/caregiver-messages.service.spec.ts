import { NotFoundException } from '@nestjs/common';
import { CaregiverMessagesService } from './caregiver-messages.service';

describe('CaregiverMessagesService', () => {
  let service: CaregiverMessagesService;
  let caregiverMessagesRepo: any;
  let auditService: any;

  const existingRow = {
    id: 'msg-1',
    event: 'job_applied',
    icon: 'person_add',
    message: 'Successfully applied to job {job_id}',
    display_order: 10,
    enabled: true,
    created_by: 'admin-1',
    updated_by: 'admin-1',
    created_at: new Date(),
    updated_at: new Date(),
  };

  beforeEach(() => {
    caregiverMessagesRepo = {
      findEnabled: jest.fn(),
      findAll: jest.fn(),
      findById: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    };
    auditService = { log: jest.fn() };
    service = new CaregiverMessagesService(caregiverMessagesRepo, auditService);
  });

  describe('get', () => {
    it('returns only enabled rows from the repository', async () => {
      caregiverMessagesRepo.findEnabled.mockResolvedValue([existingRow]);
      const result = await service.get();
      expect(result).toEqual([existingRow]);
      expect(caregiverMessagesRepo.findEnabled).toHaveBeenCalled();
    });
  });

  describe('adminList', () => {
    it('returns every row regardless of enabled state', async () => {
      caregiverMessagesRepo.findAll.mockResolvedValue([existingRow]);
      const result = await service.adminList();
      expect(result).toEqual([existingRow]);
    });
  });

  describe('adminCreate', () => {
    it('creates the row, defaults enabled to true when omitted, and audit-logs it', async () => {
      const dto = {
        event: 'job_applied',
        icon: 'person_add',
        message: 'New tip {job_id}',
        display_order: 50,
      };
      caregiverMessagesRepo.create.mockResolvedValue({ ...existingRow, ...dto, id: 'msg-2' });

      const result = await service.adminCreate('admin-1', dto as any, '127.0.0.1');

      expect(caregiverMessagesRepo.create).toHaveBeenCalledWith({ ...dto, enabled: true }, 'admin-1');
      expect(result.id).toBe('msg-2');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'caregiver_message_created',
          entityType: 'caregiver_messages',
          entityId: 'msg-2',
          ipAddress: '127.0.0.1',
        }),
      );
    });

    it('respects an explicit enabled: false', async () => {
      const dto = { event: 'welcome', icon: 'waving_hand', message: 'Hi', display_order: 10, enabled: false };
      caregiverMessagesRepo.create.mockResolvedValue({ ...existingRow, ...dto });

      await service.adminCreate('admin-1', dto as any, null);

      expect(caregiverMessagesRepo.create).toHaveBeenCalledWith(dto, 'admin-1');
    });
  });

  describe('adminUpdate', () => {
    it('updates the row and audit-logs before/after values', async () => {
      caregiverMessagesRepo.findById.mockResolvedValue(existingRow);
      const updatedRow = { ...existingRow, message: 'Updated tip' };
      caregiverMessagesRepo.update.mockResolvedValue(updatedRow);

      const dto = { message: 'Updated tip' };
      const result = await service.adminUpdate('admin-1', 'msg-1', dto as any, '127.0.0.1');

      expect(result).toEqual(updatedRow);
      expect(caregiverMessagesRepo.update).toHaveBeenCalledWith('msg-1', dto, 'admin-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'caregiver_message_updated',
          entityType: 'caregiver_messages',
          entityId: 'msg-1',
          beforeValue: existingRow,
          afterValue: updatedRow,
        }),
      );
    });

    it('throws NotFoundException when the message does not exist', async () => {
      caregiverMessagesRepo.findById.mockResolvedValue(null);

      await expect(service.adminUpdate('admin-1', 'missing', {} as any, null)).rejects.toBeInstanceOf(
        NotFoundException,
      );
      expect(caregiverMessagesRepo.update).not.toHaveBeenCalled();
    });
  });

  describe('adminDelete', () => {
    it('deletes the row and audit-logs the before value', async () => {
      caregiverMessagesRepo.findById.mockResolvedValue(existingRow);

      const result = await service.adminDelete('admin-1', 'msg-1', '127.0.0.1');

      expect(caregiverMessagesRepo.delete).toHaveBeenCalledWith('msg-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'caregiver_message_deleted',
          entityType: 'caregiver_messages',
          entityId: 'msg-1',
          beforeValue: existingRow,
        }),
      );
      expect(result).toEqual({ message: 'Message deleted' });
    });

    it('throws NotFoundException when the message does not exist', async () => {
      caregiverMessagesRepo.findById.mockResolvedValue(null);

      await expect(service.adminDelete('admin-1', 'missing', null)).rejects.toBeInstanceOf(NotFoundException);
      expect(caregiverMessagesRepo.delete).not.toHaveBeenCalled();
    });
  });
});
