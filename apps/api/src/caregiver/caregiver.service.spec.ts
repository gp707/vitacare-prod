import { CaregiverService } from './caregiver.service';
import { VerificationStatus } from '@vitacare/shared-constants';

describe('CaregiverService', () => {
  let service: CaregiverService;
  let db: any;
  let usersRepo: any;
  let profilesRepo: any;
  let languagesRepo: any;
  let preferredCitiesRepo: any;
  let preferredDutyTypesRepo: any;
  let uploadService: any;
  let emailService: any;
  let auditService: any;

  const fullProfile = {
    id: 'profile-1',
    user_id: 'user-1',
    gender: 'female',
    age: 28,
    verification_status: VerificationStatus.PENDING_CALL,
    full_name: 'Test Caregiver',
    phone: '+919876543210',
    email: null,
    selfie_photo_url: null,
    highest_qualification: null,
    qualification_document_url: null,
    aadhaar_document_url: null,
    other_document_urls: [],
    religion: null,
    terms_accepted: true,
    rejection_message: null,
    has_pending_edits: false,
    verified_at: null,
    min_salary_per_day: null,
    min_salary_per_month: null,
    created_at: new Date(),
  };

  beforeEach(() => {
    db = {
      withTransaction: jest.fn((fn: any) => fn({ query: jest.fn() })),
    };
    usersRepo = {
      updateFullName: jest.fn(),
      updateCodeHash: jest.fn(),
      updateFcmToken: jest.fn(),
      updatePhone: jest.fn(),
      findByPhoneAndRoles: jest.fn().mockResolvedValue(null),
    };
    profilesRepo = {
      findFullByUserId: jest.fn(),
      findFullById: jest.fn(),
      editFields: jest.fn(),
      flagPendingEdits: jest.fn(),
      markForReReview: jest.fn(),
      setSelfieUrl: jest.fn(),
      setQualificationDocumentUrl: jest.fn(),
      setAadhaarDocumentUrl: jest.fn(),
      getOtherDocumentUrls: jest.fn().mockResolvedValue([]),
      appendOtherDocumentUrl: jest.fn(),
      markAvailable: jest.fn(),
    };
    languagesRepo = { findByProfileId: jest.fn().mockResolvedValue([]), replaceForProfile: jest.fn() };
    preferredCitiesRepo = {
      findByProfileId: jest.fn().mockResolvedValue([]),
      replaceForProfile: jest.fn(),
    };
    preferredDutyTypesRepo = {
      findByProfileId: jest.fn().mockResolvedValue([]),
      replaceForProfile: jest.fn(),
    };
    uploadService = {
      uploadFile: jest.fn(),
      getSignedUrl: jest.fn().mockResolvedValue('https://signed/url'),
      getSignedUrlOrNull: jest.fn().mockResolvedValue(null),
      extractExtension: jest.fn().mockReturnValue('jpg'),
    };
    emailService = { sendToAdmin: jest.fn(), send: jest.fn() };
    auditService = { log: jest.fn() };

    service = new CaregiverService(
      db,
      usersRepo,
      profilesRepo,
      languagesRepo,
      preferredCitiesRepo,
      preferredDutyTypesRepo,
      uploadService,
      emailService,
      auditService,
    );
  });

  describe('getProfile', () => {
    it('throws PROFILE_019 when no profile exists for the user', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(null);
      await expect(service.getProfile('user-1')).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('returns the full profile shape with resolved signed URLs', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        selfie_photo_url: 'profile-1/selfie.jpg',
      });
      uploadService.getSignedUrlOrNull.mockResolvedValueOnce('https://signed/selfie');
      languagesRepo.findByProfileId.mockResolvedValue(['hindi', 'english']);
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore', 'mumbai']);
      preferredDutyTypesRepo.findByProfileId.mockResolvedValue(['day_duty']);

      const result = await service.getProfile('user-1');
      expect(result.selfie_photo_url).toBe('https://signed/selfie');
      expect(result.languages).toEqual(['hindi', 'english']);
      expect(result.preferred_cities).toEqual(['bangalore', 'mumbai']);
      expect(result.preferred_duty_types).toEqual(['day_duty']);
      expect(result.verification_status).toBe('pending_call');
    });

    it('includes min_salary_per_day/min_salary_per_month in the response', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        min_salary_per_day: 1500,
        min_salary_per_month: null,
      });

      const result = await service.getProfile('user-1');
      expect(result.min_salary_per_day).toBe(1500);
      expect(result.min_salary_per_month).toBeNull();
    });
  });

  describe('getApplicantProfile', () => {
    it('throws GEN_002 when no profile exists for that id', async () => {
      profilesRepo.findFullById.mockResolvedValue(null);
      await expect(service.getApplicantProfile('profile-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns the full profile — email, document URLs, job-search preferences, and rejection_message all included', async () => {
      profilesRepo.findFullById.mockResolvedValue({
        ...fullProfile,
        email: 'nita@example.com',
        selfie_photo_url: 'profile-1/selfie.jpg',
        qualification_document_url: 'profile-1/qual.pdf',
        aadhaar_document_url: 'profile-1/aadhaar.pdf',
        other_document_urls: ['profile-1/other.pdf'],
        rejection_message: 'stale',
      });
      uploadService.getSignedUrlOrNull.mockImplementation(async (_bucket: string, path: string | null) =>
        path ? `https://signed/${path}` : null,
      );
      uploadService.getSignedUrl.mockImplementation(async (_bucket: string, path: string) => `https://signed/${path}`);
      languagesRepo.findByProfileId.mockResolvedValue(['hindi']);
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore']);
      preferredDutyTypesRepo.findByProfileId.mockResolvedValue(['day_duty']);

      const result = await service.getApplicantProfile('profile-1');
      expect(result.selfie_photo_url).toBe('https://signed/profile-1/selfie.jpg');
      expect(result.languages).toEqual(['hindi']);
      expect(result.full_name).toBe('Test Caregiver');
      expect(result.email).toBe('nita@example.com');
      expect(result.qualification_document_url).toBe('https://signed/profile-1/qual.pdf');
      expect(result.aadhaar_document_url).toBe('https://signed/profile-1/aadhaar.pdf');
      expect(result.other_document_urls).toEqual(['https://signed/profile-1/other.pdf']);
      expect(result.rejection_message).toBe('stale');
      expect(result.preferred_cities).toEqual(['bangalore']);
      expect(result.preferred_duty_types).toEqual(['day_duty']);
    });
  });

  describe('editProfile', () => {
    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(null);
      await expect(
        service.editProfile('user-1', { age: 30 }),
      ).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('writes age/highest_qualification via editFields and flags has_pending_edits, without changing verification_status when not rejected', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        age: 28,
        highest_qualification: 'non_nursing',
        verification_status: VerificationStatus.AVAILABLE,
      });

      const result = await service.editProfile('user-1', {
        age: 31,
        highest_qualification: 'anm_student_backlog' as any,
      });

      expect(profilesRepo.editFields).toHaveBeenCalledWith('profile-1', {
        age: 31,
        highest_qualification: 'anm_student_backlog',
      });
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(result).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'available',
      });
      expect(usersRepo.updateFullName).not.toHaveBeenCalled();
    });

    it('writes min_salary_per_day/min_salary_per_month via editFields, without changing verification_status when not rejected', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        min_salary_per_day: null,
        min_salary_per_month: null,
        verification_status: VerificationStatus.AVAILABLE,
      });

      const result = await service.editProfile('user-1', {
        min_salary_per_day: 1500,
        min_salary_per_month: 25000,
      });

      expect(profilesRepo.editFields).toHaveBeenCalledWith('profile-1', {
        age: undefined,
        highest_qualification: undefined,
        min_salary_per_day: 1500,
        min_salary_per_month: 25000,
      });
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(result.verification_status).toBe('available');
    });

    it('replaces preferred_duty_types and flags pending edits even when no scalar field changed', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      preferredDutyTypesRepo.findByProfileId.mockResolvedValue(['live_in']);

      const result = await service.editProfile('user-1', {
        preferred_duty_types: ['day_duty', 'night_duty'] as any,
      });

      expect(preferredDutyTypesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        ['day_duty', 'night_duty'],
        expect.anything(),
      );
      expect(profilesRepo.editFields).not.toHaveBeenCalled();
      expect(profilesRepo.flagPendingEdits).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'available',
      });
    });

    it('does not replace preferred_duty_types when the (order-insensitive) set is unchanged', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      preferredDutyTypesRepo.findByProfileId.mockResolvedValue(['day_duty', 'night_duty']);

      await service.editProfile('user-1', {
        preferred_duty_types: ['night_duty', 'day_duty'] as any,
      });

      expect(preferredDutyTypesRepo.replaceForProfile).not.toHaveBeenCalled();
      expect(profilesRepo.flagPendingEdits).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('clearing preferred_duty_types to an empty array is a real change when one was previously set', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      preferredDutyTypesRepo.findByProfileId.mockResolvedValue(['live_in']);

      await service.editProfile('user-1', { preferred_duty_types: [] as any });

      expect(preferredDutyTypesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        [],
        expect.anything(),
      );
    });

    it('replaces languages when provided and different', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      languagesRepo.findByProfileId.mockResolvedValue(['hindi']);

      await service.editProfile('user-1', { languages: ['hindi', 'tamil'] as any });

      expect(languagesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        ['hindi', 'tamil'],
        expect.anything(),
      );
    });

    it('replaces preferred_cities and flags pending edits even when no scalar field changed', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore']);

      const result = await service.editProfile('user-1', {
        preferred_cities: ['mumbai', 'pune'] as any,
      });

      expect(preferredCitiesRepo.replaceForProfile).toHaveBeenCalledWith(
        'profile-1',
        ['mumbai', 'pune'],
        expect.anything(),
      );
      expect(profilesRepo.editFields).not.toHaveBeenCalled();
      expect(profilesRepo.flagPendingEdits).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'available',
      });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { preferred_cities: ['bangalore'] },
          afterValue: { preferred_cities: ['mumbai', 'pune'] },
        }),
      );
    });

    it('does not write or email/audit-log when nothing actually changed', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        highest_qualification: 'anm_student_backlog',
        verification_status: VerificationStatus.AVAILABLE,
      });

      await service.editProfile('user-1', { highest_qualification: 'anm_student_backlog' as any });

      expect(profilesRepo.editFields).not.toHaveBeenCalled();
      expect(emailService.sendToAdmin).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('does not replace preferred_cities when the (order-insensitive) set is unchanged', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore', 'mumbai']);

      await service.editProfile('user-1', { preferred_cities: ['mumbai', 'bangalore'] as any });

      expect(preferredCitiesRepo.replaceForProfile).not.toHaveBeenCalled();
      expect(profilesRepo.flagPendingEdits).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('auto-resubmits (sends back to pending_call) when a rejected caregiver changes anything', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        age: 28,
        verification_status: VerificationStatus.REJECTED,
      });

      const result = await service.editProfile('user-1', { age: 31 });

      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
      expect(result.verification_status).toBe('pending_call');
    });

    it('does not auto-resubmit a rejected caregiver when nothing changed', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        age: 28,
        verification_status: VerificationStatus.REJECTED,
      });

      await service.editProfile('user-1', { age: 28 });

      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
    });

    it('does not auto-resubmit an available caregiver (only rejected gets the any-edit auto-resubmit)', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        age: 28,
        verification_status: VerificationStatus.AVAILABLE,
      });

      const result = await service.editProfile('user-1', { age: 31 });

      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(result.verification_status).toBe('available');
    });
  });

  describe('uploadSelfie', () => {
    it('throws UPLOAD_001 when no file is provided', async () => {
      await expect(service.uploadSelfie('user-1', undefined)).rejects.toMatchObject({
        code: 'UPLOAD_001',
      });
    });

    it('uploads to the correct path and updates the profile', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile);
      const file = { originalname: 'me.png', buffer: Buffer.from('x'), mimetype: 'image/png' } as any;
      uploadService.extractExtension.mockReturnValue('png');

      const result = await service.uploadSelfie('user-1', file);
      expect(uploadService.uploadFile).toHaveBeenCalledWith(
        'caregiver-documents',
        'profile-1/selfie.png',
        file.buffer,
        'image/png',
      );
      expect(profilesRepo.setSelfieUrl).toHaveBeenCalledWith('profile-1', 'profile-1/selfie.png');
      expect(result.file_path).toBe('caregiver-documents/profile-1/selfie.png');
    });

    it('auto-resubmits a rejected caregiver', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
      });
      const file = { originalname: 'me.png', buffer: Buffer.from('x'), mimetype: 'image/png' } as any;
      await service.uploadSelfie('user-1', file);
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
    });
  });

  describe('uploadDocument', () => {
    const file = { originalname: 'doc.pdf', buffer: Buffer.from('x'), mimetype: 'application/pdf' } as any;

    beforeEach(() => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile);
      uploadService.extractExtension.mockReturnValue('pdf');
    });

    it('throws UPLOAD_001 when no file is provided', async () => {
      await expect(
        service.uploadDocument('user-1', { document_type: 'qualification' as any }, undefined),
      ).rejects.toMatchObject({ code: 'UPLOAD_001' });
    });

    it('sets the qualification document URL', async () => {
      await service.uploadDocument('user-1', { document_type: 'qualification' as any }, file);
      expect(profilesRepo.setQualificationDocumentUrl).toHaveBeenCalledWith(
        'profile-1',
        'profile-1/qualification.pdf',
      );
    });

    it('sets the aadhaar document URL', async () => {
      await service.uploadDocument('user-1', { document_type: 'aadhaar' as any }, file);
      expect(profilesRepo.setAadhaarDocumentUrl).toHaveBeenCalledWith(
        'profile-1',
        'profile-1/aadhaar.pdf',
      );
    });

    it('appends an other document at the next index', async () => {
      profilesRepo.getOtherDocumentUrls.mockResolvedValue(['profile-1/other_1.pdf']);
      await service.uploadDocument('user-1', { document_type: 'other' as any }, file);
      expect(profilesRepo.appendOtherDocumentUrl).toHaveBeenCalledWith(
        'profile-1',
        'profile-1/other_2.pdf',
      );
    });

    it('throws UPLOAD_003 when 3 other documents already exist', async () => {
      profilesRepo.getOtherDocumentUrls.mockResolvedValue([
        'profile-1/other_1.pdf',
        'profile-1/other_2.pdf',
        'profile-1/other_3.pdf',
      ]);
      await expect(
        service.uploadDocument('user-1', { document_type: 'other' as any }, file),
      ).rejects.toMatchObject({ code: 'UPLOAD_003' });
    });

    it('re-uploading aadhaar on an available profile sends it back for review', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      await service.uploadDocument('user-1', { document_type: 'aadhaar' as any }, file);
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
    });

    it('re-uploading aadhaar on a pending_call profile does not touch status', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile); // pending_call
      await service.uploadDocument('user-1', { document_type: 'aadhaar' as any }, file);
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
    });

    it('re-uploading aadhaar on a rejected profile auto-resubmits', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
      });
      await service.uploadDocument('user-1', { document_type: 'aadhaar' as any }, file);
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
    });

    it('re-uploading qualification never triggers review for an available caregiver', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      await service.uploadDocument('user-1', { document_type: 'qualification' as any }, file);
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
    });

    it('re-uploading qualification auto-resubmits a rejected caregiver', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
      });
      await service.uploadDocument('user-1', { document_type: 'qualification' as any }, file);
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
    });
  });

  describe('updatePhone', () => {
    it('throws AUTH_001 when the phone is already registered to someone else', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile);
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ id: 'someone-else' });
      await expect(
        service.updatePhone('user-1', { phone: '+919999999999' }),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
    });

    it('no-ops (still succeeds) when the phone is unchanged', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile);
      const result = await service.updatePhone('user-1', { phone: fullProfile.phone });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
      expect(usersRepo.findByPhoneAndRoles).not.toHaveBeenCalled();
      expect(result.verification_status).toBe(fullProfile.verification_status);
    });

    it('updates the phone and sends an available caregiver back for review', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      const result = await service.updatePhone('user-1', { phone: '+919999999999' });
      expect(usersRepo.updatePhone).toHaveBeenCalledWith('user-1', '+919999999999');
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
      expect(result.verification_status).toBe('pending_call');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'phone_changed' }),
      );
    });

    it('changing phone also sends a rejected caregiver back for review', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
      });
      const result = await service.updatePhone('user-1', { phone: '+919999999999' });
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
      expect(result.verification_status).toBe('pending_call');
    });

    it('updates the phone without touching status when pending_call', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.PENDING_CALL,
      });
      const result = await service.updatePhone('user-1', { phone: '+919999999999' });
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(result.verification_status).toBe('pending_call');
    });
  });

  describe('updateCode', () => {
    it('hashes and stores the new code, never touching verification_status', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      const result = await service.updateCode('user-1', { code: '9876' });
      expect(usersRepo.updateCodeHash).toHaveBeenCalledWith('user-1', expect.any(String));
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'code_changed' }),
      );
      expect(result).toEqual({ message: 'Login code updated' });
    });
  });

  describe('getVerificationStatus', () => {
    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(null);
      await expect(service.getVerificationStatus('user-1')).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it('returns status fields', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
        rejection_message: 'Aadhaar unclear',
      });
      const result = await service.getVerificationStatus('user-1');
      expect(result).toEqual({
        verification_status: 'rejected',
        rejection_message: 'Aadhaar unclear',
        verified_at: null,
      });
    });
  });

  describe('markAvailable', () => {
    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(null);
      await expect(service.markAvailable('user-1', null)).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it('throws PROFILE_022 from pending_call', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.PENDING_CALL,
      });
      await expect(service.markAvailable('user-1', null)).rejects.toMatchObject({
        code: 'PROFILE_022',
      });
      expect(profilesRepo.markAvailable).not.toHaveBeenCalled();
    });

    it('throws PROFILE_022 from rejected', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
      });
      await expect(service.markAvailable('user-1', null)).rejects.toMatchObject({
        code: 'PROFILE_022',
      });
      expect(profilesRepo.markAvailable).not.toHaveBeenCalled();
    });

    it('is a no-op (no write, no audit log) when already available', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      const result = await service.markAvailable('user-1', null);
      expect(result).toEqual({
        message: 'You are already marked as available',
        verification_status: 'available',
        already_available: true,
      });
      expect(profilesRepo.markAvailable).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('updates from unavailable to available and audit-logs it', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.UNAVAILABLE,
      });
      const result = await service.markAvailable('user-1', '127.0.0.1');
      expect(profilesRepo.markAvailable).toHaveBeenCalledWith('profile-1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'status_changed',
          entityId: 'profile-1',
          beforeValue: { verification_status: 'unavailable' },
          afterValue: { verification_status: 'available' },
          ipAddress: '127.0.0.1',
        }),
      );
      expect(result).toEqual({
        message: 'Status updated',
        verification_status: 'available',
        already_available: false,
      });
    });

    it('updates from assigned to available — self-service unassign, only the caregiver status changes', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.ASSIGNED,
      });
      const result = await service.markAvailable('user-1', null);
      expect(profilesRepo.markAvailable).toHaveBeenCalledWith('profile-1');
      expect(result.verification_status).toBe('available');
    });
  });

  describe('updateFcmToken', () => {
    it('stores the token and returns a success message', async () => {
      const result = await service.updateFcmToken('user-1', { token: 'abc123' });
      expect(usersRepo.updateFcmToken).toHaveBeenCalledWith('user-1', 'abc123');
      expect(result).toEqual({ message: 'FCM token updated' });
    });
  });
});
