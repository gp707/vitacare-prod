import * as bcrypt from 'bcrypt';
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
  let documentsRepo: any;
  let usersRepo: any;
  let individualsRepo: any;
  let organisationsRepo: any;
  let jobsRepo: any;
  let organisationRequirementsRepo: any;
  let db: any;

  const detail = {
    id: 'profile-1',
    user_id: 'user-1',
    caregiver_number: 542,
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
      deleteFile: jest.fn(),
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
    documentsRepo = {
      recordVersion: jest.fn(),
      listByProfileId: jest.fn().mockResolvedValue([]),
      findById: jest.fn(),
      deleteById: jest.fn(),
    };
    usersRepo = { updateFullName: jest.fn(), findById: jest.fn(), updatePasswordHash: jest.fn() };
    individualsRepo = { countNewLast7Days: jest.fn().mockResolvedValue(0) };
    organisationsRepo = { countNewLast7Days: jest.fn().mockResolvedValue(0) };
    jobsRepo = { countPendingApproval: jest.fn().mockResolvedValue(0) };
    organisationRequirementsRepo = { countPendingApproval: jest.fn().mockResolvedValue(0) };
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
      documentsRepo,
      usersRepo,
      individualsRepo,
      organisationsRepo,
      jobsRepo,
      organisationRequirementsRepo,
      db,
    );
  });

  describe('getDashboardStats', () => {
    it('merges caregiver stats with jobs-pending-approval (jobs + organisation requirements combined) and new organisation/individual counts', async () => {
      caregiversRepo.getDashboardStats.mockResolvedValue({
        total_caregivers: 10,
        pending_call: 2,
        available: 5,
        unavailable: 1,
        assigned: 1,
        rejected: 1,
        pending_edits_count: 0,
        new_registrations_24h: 1,
        new_registrations_7d: 3,
      });
      jobsRepo.countPendingApproval.mockResolvedValue(4);
      organisationRequirementsRepo.countPendingApproval.mockResolvedValue(2);
      organisationsRepo.countNewLast7Days.mockResolvedValue(3);
      individualsRepo.countNewLast7Days.mockResolvedValue(7);

      const result = await service.getDashboardStats();

      expect(result).toEqual(
        expect.objectContaining({
          total_caregivers: 10,
          jobs_pending_approval: 6,
          new_organisations_7d: 3,
          new_individuals_7d: 7,
        }),
      );
    });
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

    it('passes gender and city (preferred city) filters through to the repository', async () => {
      caregiversRepo.listCaregivers.mockResolvedValue({ items: [], total: 0 });

      await service.listCaregivers({
        page: 1,
        limit: 20,
        sort: 'created_at',
        order: 'desc',
        gender: 'female',
        city: 'bangalore',
      } as any);

      expect(caregiversRepo.listCaregivers).toHaveBeenCalledWith(
        expect.objectContaining({ gender: 'female', preferredCity: 'bangalore' }),
        expect.objectContaining({ page: 1, limit: 20 }),
      );
    });

    it('includes caregiver_number in each returned item (regression — was silently dropped before)', async () => {
      caregiversRepo.listCaregivers.mockResolvedValue({
        items: [{ ...detail, profile_id: 'profile-1' }],
        total: 1,
      });

      const result = await service.listCaregivers({ page: 1, limit: 20, sort: 'created_at', order: 'desc' } as any);
      expect(result.data[0].caregiver_number).toBe(542);
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
        search: 'NUR-500',
      } as any);

      expect(auditLogsRepo.list).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', action: 'status_changed', search: 'NUR-500' }),
        expect.objectContaining({ order: 'asc', page: 2, limit: 20 }),
      );
      expect(result.meta).toEqual({ page: 2, limit: 20, total: 45, totalPages: 3 });
    });

    it('maps job_id/requirement_id filters through to the repository', async () => {
      auditLogsRepo.list.mockResolvedValue({ items: [], total: 0 });

      await service.listAuditLogs({
        page: 1,
        limit: 20,
        sort: 'created_at',
        order: 'desc',
        job_id: 'job-1',
        requirement_id: 'req-1',
      } as any);

      expect(auditLogsRepo.list).toHaveBeenCalledWith(
        expect.objectContaining({ jobId: 'job-1', requirementId: 'req-1' }),
        expect.anything(),
      );
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
        admin_job_number: null,
        patient_job_number: null,
        job_id: null,
        target_user_role: 'caregiver',
        target_caregiver_number: 542,
        target_patient_number: null,
        target_org_number: null,
        requirement_number: null,
        requirement_id: null,
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

    it('resolves target_user_role/patient_number for an individual, and org_number for an organisation', async () => {
      const individualRow = {
        id: 'log-3',
        target_user_role: 'individual',
        target_caregiver_number: null,
        target_patient_number: 501,
        target_org_number: null,
      };
      const orgRow = {
        id: 'log-4',
        target_user_role: 'organisation',
        target_caregiver_number: null,
        target_patient_number: null,
        target_org_number: 503,
      };
      auditLogsRepo.list.mockResolvedValue({ items: [individualRow, orgRow], total: 2 });

      const result = await service.listAuditLogs({ page: 1, limit: 20, sort: 'created_at', order: 'desc' } as any);

      expect(result.data[0]).toMatchObject({ target_user_role: 'individual', target_patient_number: 501 });
      expect(result.data[1]).toMatchObject({ target_user_role: 'organisation', target_org_number: 503 });
    });

    it('passes through target_caregiver_profile_id, so admin-web can link a caregiver target to their detail page', async () => {
      const row = {
        id: 'log-5',
        target_user_role: 'caregiver',
        target_caregiver_number: 542,
        target_caregiver_profile_id: 'profile-542',
      };
      auditLogsRepo.list.mockResolvedValue({ items: [row], total: 1 });

      const result = await service.listAuditLogs({ page: 1, limit: 20, sort: 'created_at', order: 'desc' } as any);

      expect(result.data[0]).toMatchObject({ target_caregiver_profile_id: 'profile-542' });
    });

    it('passes through requirement_number/requirement_id for organisation-requirement-related entries', async () => {
      const row = {
        id: 'log-5',
        action: 'org_requirement_posted',
        entity_type: 'organisation_requirements',
        requirement_number: 507,
        requirement_id: 'req-1',
      };
      auditLogsRepo.list.mockResolvedValue({ items: [row], total: 1 });

      const result = await service.listAuditLogs({ page: 1, limit: 20, sort: 'created_at', order: 'desc' } as any);

      expect(result.data[0]).toMatchObject({ requirement_number: 507, requirement_id: 'req-1' });
    });

    it('passes through the repository-resolved admin_job_number/patient_job_number/job_id for job-related entries', async () => {
      const row = {
        id: 'log-2',
        user_id: 'admin-1',
        user_name: 'Admin One',
        target_user_id: null,
        target_user_name: null,
        action: 'job_posted',
        entity_type: 'jobs',
        entity_id: 'job-1',
        admin_job_number: 512,
        patient_job_number: null,
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

      expect(result.data[0]).toMatchObject({
        admin_job_number: 512,
        patient_job_number: null,
        job_id: 'job-1',
      });
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

    it('uploads to a unique versioned path (never overwriting the previous one), records the version, and audit-logs before/after', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, selfie_photo_url: 'profile-1/selfie_1000.jpg' });
      const file = { originalname: 'new.png', buffer: Buffer.from('x'), mimetype: 'image/png' } as any;
      uploadService.extractExtension.mockReturnValue('png');

      const result = await service.uploadSelfie('profile-1', 'admin-1', file);

      const expectedPath = expect.stringMatching(/^profile-1\/selfie_\d+\.png$/);
      expect(uploadService.uploadFile).toHaveBeenCalledWith(
        'caregiver-documents',
        expectedPath,
        file.buffer,
        'image/png',
      );
      expect(profilesRepo.setSelfieUrl).toHaveBeenCalledWith('profile-1', expectedPath);
      expect(documentsRepo.recordVersion).toHaveBeenCalledWith(
        'profile-1',
        'selfie',
        expectedPath,
        'admin-1',
        'admin',
      );
      expect(result.message).toBe('Selfie uploaded');
      expect(result.file_path).toMatch(/^caregiver-documents\/profile-1\/selfie_\d+\.png$/);
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

    it('sets the qualification document URL to a unique versioned path, records the version, and logs had_file: false when none existed', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      uploadService.extractExtension.mockReturnValue('pdf');

      await service.uploadDocument('profile-1', 'admin-1', { document_type: 'qualification' } as any, file);

      const expectedPath = expect.stringMatching(/^profile-1\/qualification_\d+\.pdf$/);
      expect(profilesRepo.setQualificationDocumentUrl).toHaveBeenCalledWith('profile-1', expectedPath);
      expect(documentsRepo.recordVersion).toHaveBeenCalledWith(
        'profile-1',
        'qualification',
        expectedPath,
        'admin-1',
        'admin',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { document_type: 'qualification', had_file: false },
          afterValue: { document_type: 'qualification', had_file: true },
        }),
      );
    });

    it('sets the aadhaar document URL to a unique versioned path, never overwriting the previous one', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({ ...detail, aadhaar_document_url: 'p/old.pdf' });
      uploadService.extractExtension.mockReturnValue('pdf');

      await service.uploadDocument('profile-1', 'admin-1', { document_type: 'aadhaar' } as any, file);

      const expectedPath = expect.stringMatching(/^profile-1\/aadhaar_\d+\.pdf$/);
      expect(profilesRepo.setAadhaarDocumentUrl).toHaveBeenCalledWith('profile-1', expectedPath);
      expect(documentsRepo.recordVersion).toHaveBeenCalledWith(
        'profile-1',
        'aadhaar',
        expectedPath,
        'admin-1',
        'admin',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { document_type: 'aadhaar', had_file: true },
        }),
      );
    });

    it('appends an other document at the next index, at a unique versioned path, recording its slot index', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      profilesRepo.getOtherDocumentUrls.mockResolvedValue(['profile-1/other_1_1000.pdf']);
      uploadService.extractExtension.mockReturnValue('pdf');

      await service.uploadDocument('profile-1', 'admin-1', { document_type: 'other' } as any, file);

      const expectedPath = expect.stringMatching(/^profile-1\/other_2_\d+\.pdf$/);
      expect(profilesRepo.appendOtherDocumentUrl).toHaveBeenCalledWith('profile-1', expectedPath);
      expect(documentsRepo.recordVersion).toHaveBeenCalledWith(
        'profile-1',
        'other',
        expectedPath,
        'admin-1',
        'admin',
        2,
      );
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

  describe('getDocumentHistory', () => {
    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      await expect(service.getDocumentHistory('missing')).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('returns every recorded version with a fresh signed URL, newest first', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      documentsRepo.listByProfileId.mockResolvedValue([
        {
          id: 'doc-2',
          document_type: 'selfie',
          slot_index: null,
          path: 'profile-1/selfie_2000.jpg',
          uploaded_by: 'user-1',
          uploaded_by_name: 'Ramesh Kumar',
          uploaded_by_role: 'caregiver',
          created_at: new Date('2026-08-02T00:00:00Z'),
        },
        {
          id: 'doc-1',
          document_type: 'selfie',
          slot_index: null,
          path: 'profile-1/selfie_1000.jpg',
          uploaded_by: 'admin-1',
          uploaded_by_name: 'Admin One',
          uploaded_by_role: 'admin',
          created_at: new Date('2026-08-01T00:00:00Z'),
        },
      ]);
      uploadService.getSignedUrl.mockImplementation(async (_bucket: string, path: string) => `https://signed/${path}`);

      const result = await service.getDocumentHistory('profile-1');

      expect(documentsRepo.listByProfileId).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual([
        expect.objectContaining({
          id: 'doc-2',
          document_type: 'selfie',
          signed_url: 'https://signed/profile-1/selfie_2000.jpg',
          uploaded_by_name: 'Ramesh Kumar',
          uploaded_by_role: 'caregiver',
        }),
        expect.objectContaining({
          id: 'doc-1',
          document_type: 'selfie',
          signed_url: 'https://signed/profile-1/selfie_1000.jpg',
          uploaded_by_name: 'Admin One',
          uploaded_by_role: 'admin',
        }),
      ]);
    });
  });

  describe('deleteDocumentVersion', () => {
    it('throws PROFILE_019 when the profile does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(null);
      await expect(
        service.deleteDocumentVersion('missing', 'doc-1', 'admin-1', null),
      ).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('throws UPLOAD_006 when the version does not exist', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      documentsRepo.findById.mockResolvedValue(null);
      await expect(
        service.deleteDocumentVersion('profile-1', 'missing-doc', 'admin-1', null),
      ).rejects.toMatchObject({ code: 'UPLOAD_006' });
    });

    it('throws UPLOAD_006 when the version belongs to a different profile', async () => {
      caregiversRepo.getDetailById.mockResolvedValue(detail);
      documentsRepo.findById.mockResolvedValue({
        id: 'doc-1',
        profile_id: 'someone-elses-profile',
        document_type: 'selfie',
        slot_index: null,
        path: 'someone-elses-profile/selfie_1000.jpg',
      });
      await expect(
        service.deleteDocumentVersion('profile-1', 'doc-1', 'admin-1', null),
      ).rejects.toMatchObject({ code: 'UPLOAD_006' });
    });

    it('throws UPLOAD_007 and never deletes the file/row when the version is the current selfie', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({
        ...detail,
        selfie_photo_url: 'profile-1/selfie_2000.jpg',
      });
      documentsRepo.findById.mockResolvedValue({
        id: 'doc-2',
        profile_id: 'profile-1',
        document_type: 'selfie',
        slot_index: null,
        path: 'profile-1/selfie_2000.jpg',
      });
      await expect(
        service.deleteDocumentVersion('profile-1', 'doc-2', 'admin-1', null),
      ).rejects.toMatchObject({ code: 'UPLOAD_007' });
      expect(uploadService.deleteFile).not.toHaveBeenCalled();
      expect(documentsRepo.deleteById).not.toHaveBeenCalled();
    });

    it('throws UPLOAD_007 when the version is one of the current "other" documents', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({
        ...detail,
        other_document_urls: ['profile-1/other_1_1000.pdf'],
      });
      documentsRepo.findById.mockResolvedValue({
        id: 'doc-other',
        profile_id: 'profile-1',
        document_type: 'other',
        slot_index: 1,
        path: 'profile-1/other_1_1000.pdf',
      });
      await expect(
        service.deleteDocumentVersion('profile-1', 'doc-other', 'admin-1', null),
      ).rejects.toMatchObject({ code: 'UPLOAD_007' });
    });

    it('deletes the storage object and the row, and audit-logs it, for a superseded (non-current) version', async () => {
      caregiversRepo.getDetailById.mockResolvedValue({
        ...detail,
        user_id: 'user-1',
        selfie_photo_url: 'profile-1/selfie_2000.jpg',
      });
      documentsRepo.findById.mockResolvedValue({
        id: 'doc-1',
        profile_id: 'profile-1',
        document_type: 'selfie',
        slot_index: null,
        path: 'profile-1/selfie_1000.jpg',
      });

      const result = await service.deleteDocumentVersion('profile-1', 'doc-1', 'admin-1', '1.2.3.4');

      expect(uploadService.deleteFile).toHaveBeenCalledWith('caregiver-documents', 'profile-1/selfie_1000.jpg');
      expect(documentsRepo.deleteById).toHaveBeenCalledWith('doc-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'user-1',
          action: 'admin_document_version_deleted',
          entityType: 'caregiver_documents',
          entityId: 'doc-1',
          beforeValue: { document_type: 'selfie', slot_index: null },
          afterValue: null,
          ipAddress: '1.2.3.4',
        }),
      );
      expect(result).toEqual({ message: 'Document version deleted' });
    });
  });

  describe('changeOwnPassword', () => {
    const existingHash = bcrypt.hashSync('OldPassw0rd', 10);

    it('throws GEN_002 when the user does not exist', async () => {
      usersRepo.findById.mockResolvedValue(null);
      await expect(
        service.changeOwnPassword('admin-1', { current_password: 'x', new_password: 'y' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws AUTH_015 when the current password is wrong', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'admin-1', password_hash: existingHash });
      await expect(
        service.changeOwnPassword(
          'admin-1',
          { current_password: 'WrongPassword', new_password: 'NewPassw0rd' } as any,
          null,
        ),
      ).rejects.toMatchObject({ code: 'AUTH_015' });
      expect(usersRepo.updatePasswordHash).not.toHaveBeenCalled();
    });

    it('throws AUTH_015 when the account has no password set at all', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'admin-1', password_hash: null });
      await expect(
        service.changeOwnPassword(
          'admin-1',
          { current_password: 'anything', new_password: 'NewPassw0rd' } as any,
          null,
        ),
      ).rejects.toMatchObject({ code: 'AUTH_015' });
    });

    it('hashes and stores the new password, and audit-logs it, when the current password is correct', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'admin-1', password_hash: existingHash });
      const result = await service.changeOwnPassword(
        'admin-1',
        { current_password: 'OldPassw0rd', new_password: 'NewPassw0rd' } as any,
        '127.0.0.1',
      );

      expect(usersRepo.updatePasswordHash).toHaveBeenCalledWith('admin-1', expect.any(String));
      const storedHash = usersRepo.updatePasswordHash.mock.calls[0][1];
      expect(await bcrypt.compare('NewPassw0rd', storedHash)).toBe(true);
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'admin_password_changed',
          entityType: 'users',
          entityId: 'admin-1',
          ipAddress: '127.0.0.1',
        }),
      );
      expect(result).toEqual({ message: 'Password updated' });
    });
  });
});
