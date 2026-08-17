import { AdminService } from './admin.service';
import { VerificationStatus } from '@vitacare/shared-constants';

describe('AdminService', () => {
  let service: AdminService;
  let caregiversRepo: any;
  let notesRepo: any;
  let languagesRepo: any;
  let preferredCitiesRepo: any;
  let uploadService: any;
  let auditLogsRepo: any;
  let auditService: any;
  let fcmService: any;
  let profilesRepo: any;
  let usersRepo: any;
  let db: any;

  const detail = {
    id: 'profile-1',
    user_id: 'user-1',
    full_name: 'Ramesh Kumar',
    phone: '+919876543210',
    email: null,
    gender: 'male',
    age: 32,
    selfie_photo_url: null,
    highest_qualification: null,
    qualification_document_url: null,
    aadhaar_document_url: null,
    other_document_urls: [],
    religion: null,
    terms_accepted: false,
    verification_status: VerificationStatus.PENDING_CALL,
    rejection_message: null,
    has_pending_edits: false,
    created_at: new Date(),
    verified_at: null,
  };

  beforeEach(() => {
    caregiversRepo = {
      getDashboardStats: jest.fn(),
      listCaregivers: jest.fn(),
      getDetailById: jest.fn(),
      updateStatus: jest.fn(),
    };
    notesRepo = { findByProfileId: jest.fn().mockResolvedValue(null), upsert: jest.fn() };
    languagesRepo = { findByProfileId: jest.fn().mockResolvedValue([]), replaceForProfile: jest.fn() };
    preferredCitiesRepo = {
      findByProfileId: jest.fn().mockResolvedValue([]),
      replaceForProfile: jest.fn(),
    };
    uploadService = {
      getSignedUrlOrNull: jest.fn().mockResolvedValue(null),
      getSignedUrl: jest.fn().mockResolvedValue('https://signed/url'),
      uploadFile: jest.fn(),
      extractExtension: jest.fn().mockReturnValue('jpg'),
    };
    auditLogsRepo = { list: jest.fn().mockResolvedValue({ items: [], total: 0 }) };
    auditService = { log: jest.fn() };
    fcmService = { sendToUser: jest.fn() };
    profilesRepo = {
      adminUpdate: jest.fn(),
      setSelfieUrl: jest.fn(),
      setQualificationDocumentUrl: jest.fn(),
      setAadhaarDocumentUrl: jest.fn(),
      getOtherDocumentUrls: jest.fn().mockResolvedValue([]),
      appendOtherDocumentUrl: jest.fn(),
    };
    usersRepo = { updateFullName: jest.fn() };
    db = { withTransaction: jest.fn((fn: any) => fn({ query: jest.fn() })) };

    service = new AdminService(
      caregiversRepo,
      notesRepo,
      auditLogsRepo,
      languagesRepo,
      preferredCitiesRepo,
      uploadService,
      auditService,
      fcmService,
      profilesRepo,
      usersRepo,
      db,
    );
  });

  describe('listCaregivers', () => {
    it('splits comma-separated languages and computes pagination meta', async () => {
      caregiversRepo.listCaregivers.mockResolvedValue({ items: [], total: 45 });

      const result = await service.listCaregivers({
        page: 2,
        limit: 20,
        sort: 'created_at',
        order: 'desc',
        language: 'hindi, english',
      } as any);

      expect(caregiversRepo.listCaregivers).toHaveBeenCalledWith(
        expect.objectContaining({ languages: ['hindi', 'english'] }),
        expect.objectContaining({ page: 2, limit: 20 }),
      );
      expect(result.meta).toEqual({ page: 2, limit: 20, total: 45, totalPages: 3 });
    });
  });

  describe('getCaregiverDetail', () => {
    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      await expect(service.getCaregiverDetail('missing')).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it('returns null admin_notes fields when no notes exist yet', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      const result = await service.getCaregiverDetail('profile-1');
      expect(result.admin_notes).toEqual({
        internal_notes: null,
        availability_remarks: null,
      });
    });

    it('includes preferred_cities from the junction table', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore', 'chennai']);
      const result = await service.getCaregiverDetail('profile-1');
      expect(result.preferred_cities).toEqual(['bangalore', 'chennai']);
    });
  });

  describe('updateStatus', () => {
    it.each([
      // The common-case flow: admin approves or rejects directly from
      // pending_call (no more call_verified/pending_verification/in_process
      // checkpoints — see architecture note in CLAUDE.md).
      [VerificationStatus.PENDING_CALL, 'available'],
      [VerificationStatus.PENDING_CALL, 'rejected'],
      // Deliberately unrestricted (no transition-matrix check) — these all
      // succeed, from any status to any status.
      [VerificationStatus.AVAILABLE, 'rejected'],
      [VerificationStatus.REJECTED, 'available'],
      [VerificationStatus.AVAILABLE, 'unavailable'],
      [VerificationStatus.UNAVAILABLE, 'assigned'],
      [VerificationStatus.ASSIGNED, 'pending_call'],
    ])('allows %s -> %s (admin override, unrestricted)', async (current, target) => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, verification_status: current });
      const result = await service.updateStatus('profile-1', 'admin-1', { status: target } as any);
      expect(result.verification_status).toBe(target);
    });

    it('sends a push notification for available/rejected, not other statuses', async () => {
      for (const status of ['unavailable', 'assigned', 'pending_call']) {
        fcmService.sendToUser.mockClear();
        caregiversRepo.getDetailById.mockResolvedValue({ ...detail, verification_status: 'available' });
        await service.updateStatus('profile-1', 'admin-1', { status } as any);
        expect(fcmService.sendToUser).not.toHaveBeenCalled();
      }

      for (const status of ['available', 'rejected']) {
        fcmService.sendToUser.mockClear();
        caregiversRepo.getDetailById.mockResolvedValue({
          ...detail,
          verification_status: VerificationStatus.PENDING_CALL,
        });
        await service.updateStatus('profile-1', 'admin-1', { status } as any);
        expect(fcmService.sendToUser).toHaveBeenCalledWith('user-1', expect.any(String), expect.any(String));
      }
    });

    it('passes the rejection_message through only for rejected', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({
        ...detail,
        verification_status: VerificationStatus.PENDING_CALL,
      });
      await service.updateStatus('profile-1', 'admin-1', {
        status: 'rejected',
        rejection_message: 'Docs unclear',
      } as any);
      expect(caregiversRepo.updateStatus).toHaveBeenCalledWith(
        'profile-1',
        'rejected',
        'Docs unclear',
        'admin-1',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'user-1',
          action: 'status_changed',
          afterValue: { verification_status: 'rejected', rejection_message: 'Docs unclear' },
        }),
      );
      expect(fcmService.sendToUser).toHaveBeenCalledWith(
        'user-1',
        expect.any(String),
        'Docs unclear',
      );
    });
  });

  describe('upsertNotes', () => {
    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      await expect(service.upsertNotes('missing', 'admin-1', {} as any)).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it('upserts and returns a success message', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      const result = await service.upsertNotes('profile-1', 'admin-1', {
        internal_notes: 'Good',
      } as any);
      expect(notesRepo.upsert).toHaveBeenCalledWith('profile-1', 'admin-1', {
        internal_notes: 'Good',
      });
      expect(result).toEqual({ message: 'Notes saved' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'user-1',
          action: 'admin_note_added',
          entityType: 'admin_notes',
          entityId: 'profile-1',
          afterValue: { internal_notes: 'Good' },
        }),
      );
    });
  });

  describe('listAuditLogs', () => {
    it('maps filters/sort through to the repository and computes pagination meta', async () => {
      auditLogsRepo.list.mockResolvedValue({ items: [], total: 45 });

      const result = await service.listAuditLogs({
        page: 2,
        limit: 20,
        sort: 'created_at',
        order: 'asc',
        user_id: 'admin-1',
        action: 'status_changed',
      } as any);

      expect(auditLogsRepo.list).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', action: 'status_changed' }),
        expect.objectContaining({ order: 'asc', page: 2, limit: 20 }),
      );
      expect(result.meta).toEqual({ page: 2, limit: 20, total: 45, totalPages: 3 });
    });

    it('maps repository rows to the documented response shape', async () => {
      const row = {
        id: 'log-1',
        user_id: 'admin-1',
        user_name: 'Admin One',
        target_user_id: 'user-1',
        target_user_name: 'Ramesh Kumar',
        action: 'status_changed',
        entity_type: 'caregiver_profiles',
        entity_id: 'profile-1',
        job_number: null,
        job_id: null,
        before_value: { verification_status: 'pending_verification' },
        after_value: { verification_status: 'available' },
        ip_address: '192.168.1.1',
        created_at: new Date('2026-08-01T14:30:00Z'),
      };
      auditLogsRepo.list.mockResolvedValue({ items: [row], total: 1 });

      const result = await service.listAuditLogs({
        page: 1,
        limit: 20,
        sort: 'created_at',
        order: 'desc',
      } as any);

      expect(result.data).toEqual([row]);
    });

    it('passes through the repository-resolved job_number/job_id for job-related entries', async () => {
      const row = {
        id: 'log-2',
        user_id: 'admin-1',
        user_name: 'Admin One',
        target_user_id: null,
        target_user_name: null,
        action: 'job_posted',
        entity_type: 'jobs',
        entity_id: 'job-1',
        job_number: 42,
        job_id: 'job-1',
        before_value: null,
        after_value: { status: 'active' },
        ip_address: null,
        created_at: new Date('2026-08-01T14:30:00Z'),
      };
      auditLogsRepo.list.mockResolvedValue({ items: [row], total: 1 });

      const result = await service.listAuditLogs({
        page: 1,
        limit: 20,
        sort: 'created_at',
        order: 'desc',
      } as any);

      expect(result.data[0]).toMatchObject({ job_number: 42, job_id: 'job-1' });
    });
  });

  describe('editProfile', () => {
    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      await expect(service.editProfile('missing', 'admin-1', {} as any)).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it('writes only the fields provided and logs only what changed', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, full_name: 'Old Name', age: 30 });

      const result = await service.editProfile('profile-1', 'admin-1', {
        full_name: 'New Name',
        age: 30,
      } as any);

      expect(usersRepo.updateFullName).toHaveBeenCalledWith('user-1', 'New Name', expect.anything());
      expect(profilesRepo.adminUpdate).toHaveBeenCalledWith(
        'profile-1',
        expect.objectContaining({ age: 30 }),
        expect.anything(),
      );
      expect(result).toEqual({ message: 'Profile updated' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'user-1',
          action: 'admin_edit_profile',
          entityType: 'caregiver_profiles',
          entityId: 'profile-1',
          beforeValue: { full_name: 'Old Name' },
          afterValue: { full_name: 'New Name' },
        }),
      );
    });

    it('does not write verification_status and skips the audit log when nothing actually changed', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, age: 30 });
      const result = await service.editProfile('profile-1', 'admin-1', { age: 30 } as any);
      expect(result).toEqual({ message: 'Profile updated' });
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('diffs languages against the current set', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      languagesRepo.findByProfileId.mockResolvedValue(['hindi']);

      await service.editProfile('profile-1', 'admin-1', { languages: ['hindi', 'tamil'] } as any);

      expect(languagesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        ['hindi', 'tamil'],
        expect.anything(),
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { languages: ['hindi'] },
          afterValue: { languages: ['hindi', 'tamil'] },
        }),
      );
    });

    it('diffs preferred_cities against the current set, order-insensitively', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore']);

      await service.editProfile('profile-1', 'admin-1', {
        preferred_cities: ['mumbai', 'bangalore'],
      } as any);

      expect(preferredCitiesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        ['mumbai', 'bangalore'],
        expect.anything(),
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { preferred_cities: ['bangalore'] },
          afterValue: { preferred_cities: ['bangalore', 'mumbai'] },
        }),
      );
    });

    it('still writes preferred_cities when provided but skips the audit log if the set is unchanged (order-insensitive)', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore', 'mumbai']);

      await service.editProfile('profile-1', 'admin-1', {
        preferred_cities: ['mumbai', 'bangalore'],
      } as any);

      expect(preferredCitiesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        ['mumbai', 'bangalore'],
        expect.anything(),
      );
      expect(auditService.log).not.toHaveBeenCalled();
    });
  });

  describe('uploadSelfie', () => {
    it('throws UPLOAD_001 when no file is provided', async () => {
      await expect(service.uploadSelfie('profile-1', 'admin-1', undefined)).rejects.toMatchObject({
        code: 'UPLOAD_001',
      });
    });

    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      const file = { originalname: 'me.png', buffer: Buffer.from('x'), mimetype: 'image/png' } as any;
      await expect(service.uploadSelfie('missing', 'admin-1', file)).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it('uploads to the correct path, overwrites, and audit-logs before/after', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, selfie_photo_url: 'profile-1/selfie.jpg' });
      const file = { originalname: 'new.png', buffer: Buffer.from('x'), mimetype: 'image/png' } as any;
      uploadService.extractExtension.mockReturnValue('png');

      const result = await service.uploadSelfie('profile-1', 'admin-1', file);

      expect(uploadService.uploadFile).toHaveBeenCalledWith(
        'caregiver-documents',
        'profile-1/selfie.png',
        file.buffer,
        'image/png',
      );
      expect(profilesRepo.setSelfieUrl).toHaveBeenCalledWith('profile-1', 'profile-1/selfie.png');
      expect(result).toEqual({
        message: 'Selfie uploaded',
        file_path: 'caregiver-documents/profile-1/selfie.png',
      });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'user-1',
          action: 'admin_document_uploaded',
          entityType: 'caregiver_profiles',
          entityId: 'profile-1',
          beforeValue: { document_type: 'selfie', had_file: true },
          afterValue: { document_type: 'selfie', had_file: true },
        }),
      );
    });
  });

  describe('uploadDocument', () => {
    const file = { originalname: 'doc.pdf', buffer: Buffer.from('x'), mimetype: 'application/pdf' } as any;

    it('throws UPLOAD_001 when no file is provided', async () => {
      await expect(
        service.uploadDocument('profile-1', 'admin-1', { document_type: 'qualification' } as any, undefined),
      ).rejects.toMatchObject({ code: 'UPLOAD_001' });
    });

    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      await expect(
        service.uploadDocument('missing', 'admin-1', { document_type: 'qualification' } as any, file),
      ).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('sets the qualification document URL and logs had_file: false when none existed', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      uploadService.extractExtension.mockReturnValue('pdf');

      await service.uploadDocument('profile-1', 'admin-1', { document_type: 'qualification' } as any, file);

      expect(profilesRepo.setQualificationDocumentUrl).toHaveBeenCalledWith(
        'profile-1',
        'profile-1/qualification.pdf',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { document_type: 'qualification', had_file: false },
          afterValue: { document_type: 'qualification', had_file: true },
        }),
      );
    });

    it('sets the aadhaar document URL', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, aadhaar_document_url: 'p/old.pdf' });
      uploadService.extractExtension.mockReturnValue('pdf');

      await service.uploadDocument('profile-1', 'admin-1', { document_type: 'aadhaar' } as any, file);

      expect(profilesRepo.setAadhaarDocumentUrl).toHaveBeenCalledWith('profile-1', 'profile-1/aadhaar.pdf');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { document_type: 'aadhaar', had_file: true },
        }),
      );
    });

    it('appends an other document at the next index', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      profilesRepo.getOtherDocumentUrls.mockResolvedValue(['profile-1/other_1.pdf']);
      uploadService.extractExtension.mockReturnValue('pdf');

      await service.uploadDocument('profile-1', 'admin-1', { document_type: 'other' } as any, file);

      expect(profilesRepo.appendOtherDocumentUrl).toHaveBeenCalledWith('profile-1', 'profile-1/other_2.pdf');
    });

    it('throws UPLOAD_003 when 3 other documents already exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      profilesRepo.getOtherDocumentUrls.mockResolvedValue([
        'profile-1/other_1.pdf',
        'profile-1/other_2.pdf',
        'profile-1/other_3.pdf',
      ]);
      await expect(
        service.uploadDocument('profile-1', 'admin-1', { document_type: 'other' } as any, file),
      ).rejects.toMatchObject({ code: 'UPLOAD_003' });
    });
  });
});
