import { CaregiverService } from './caregiver.service';
import { VerificationStatus } from '@vitacare/shared-constants';

describe('CaregiverService', () => {
  let service: CaregiverService;
  let db: any;
  let usersRepo: any;
  let profilesRepo: any;
  let languagesRepo: any;
  let serviceModesRepo: any;
  let workTypesRepo: any;
  let preferredCitiesRepo: any;
  let uploadService: any;
  let emailService: any;
  let auditService: any;

  const shortProfile = {
    id: 'profile-1',
    user_id: 'user-1',
    gender: 'female',
    age: 28,
    verification_status: VerificationStatus.PENDING_CALL,
    advanced_details_completed: false,
  };

  const fullProfile = {
    ...shortProfile,
    full_name: 'Test Caregiver',
    phone: '+919876543210',
    email: null,
    selfie_photo_url: null,
    highest_qualification: null,
    qualification_document_url: null,
    aadhaar_document_url: null,
    other_document_urls: [],
    religion: null,
    father_name: null,
    father_phone: null,
    current_address: null,
    salary: null,
    notes: null,
    terms_accepted: false,
    rejection_message: null,
    has_pending_edits: false,
    submitted_at: null,
    verified_at: null,
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
      findByPhone: jest.fn().mockResolvedValue(null),
    };
    profilesRepo = {
      findByUserId: jest.fn(),
      findFullByUserId: jest.fn(),
      updateBasic: jest.fn(),
      updateAdvanced: jest.fn(),
      editAdvancedFields: jest.fn(),
      flagPendingEdits: jest.fn(),
      markForReReview: jest.fn(),
      setSelfieUrl: jest.fn(),
      setQualificationDocumentUrl: jest.fn(),
      setAadhaarDocumentUrl: jest.fn(),
      getOtherDocumentUrls: jest.fn().mockResolvedValue([]),
      appendOtherDocumentUrl: jest.fn(),
    };
    languagesRepo = { findByProfileId: jest.fn().mockResolvedValue([]), replaceForProfile: jest.fn() };
    serviceModesRepo = { findByProfileId: jest.fn().mockResolvedValue([]) };
    workTypesRepo = { findByProfileId: jest.fn().mockResolvedValue([]) };
    preferredCitiesRepo = {
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
      serviceModesRepo,
      workTypesRepo,
      preferredCitiesRepo,
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

      const result = await service.getProfile('user-1');
      expect(result.selfie_photo_url).toBe('https://signed/selfie');
      expect(result.languages).toEqual(['hindi', 'english']);
      expect(result.service_modes).toEqual([]);
      expect(result.preferred_cities).toEqual(['bangalore', 'mumbai']);
      expect(result.verification_status).toBe('pending_call');
    });

    it('converts salary from numeric string to number', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({ ...fullProfile, salary: '28000.00' });
      const result = await service.getProfile('user-1');
      expect(result.salary).toBe(28000);
    });
  });

  describe('updateBasicProfile', () => {
    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(null);
      await expect(
        service.updateBasicProfile('user-1', {
          age: 30,
          languages: ['hindi'] as any,
        }),
      ).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('updates fields and flags has_pending_edits without changing verification_status, never touching full_name or gender', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      languagesRepo.findByProfileId.mockResolvedValue(['hindi']);

      const result = await service.updateBasicProfile('user-1', {
        age: 31,
        languages: ['hindi', 'tamil'] as any,
      });

      expect(result).toEqual({
        message: 'Profile updated',
        has_pending_edits: true,
        verification_status: 'available',
      });
      expect(usersRepo.updateFullName).not.toHaveBeenCalled();
      expect(profilesRepo.updateBasic).toHaveBeenCalledWith('profile-1', { age: 31 }, expect.anything());
    });

    it('emails the admin with only the changed fields', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        age: 28,
        verification_status: VerificationStatus.AVAILABLE,
      });
      languagesRepo.findByProfileId.mockResolvedValue(['hindi']);

      await service.updateBasicProfile('user-1', {
        age: 31,
        languages: ['hindi'] as any,
      });

      expect(emailService.sendToAdmin).toHaveBeenCalledTimes(1);
      const [, body] = emailService.sendToAdmin.mock.calls[0];
      expect(body).toContain('age: 28 -> 31');
      expect(body).not.toContain('languages:');

      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'profile_updated',
          entityType: 'caregiver_profiles',
          entityId: 'profile-1',
          beforeValue: { age: 28 },
          afterValue: { age: 31 },
        }),
      );
    });

    it('does not email or audit-log the admin when nothing actually changed', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        age: 28,
        verification_status: VerificationStatus.AVAILABLE,
      });
      languagesRepo.findByProfileId.mockResolvedValue(['hindi']);

      await service.updateBasicProfile('user-1', {
        age: 28,
        languages: ['hindi'] as any,
      });

      expect(emailService.sendToAdmin).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });
  });

  describe('submitAdvancedDetails', () => {
    const validDto = {
      highest_qualification: 'bsc_gnm_completed' as any,
      religion: 'hindu' as any,
      father_name: 'Suresh Kumar',
      father_phone: '+919876500001',
      current_address: '123 MG Road',
      terms_accepted: true,
    };

    it('throws PROFILE_008 when status is not call_verified or rejected', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.PENDING_CALL,
      });
      await expect(service.submitAdvancedDetails('user-1', validDto)).rejects.toMatchObject({
        code: 'PROFILE_008',
      });
    });

    it('throws PROFILE_017 when aadhaar is missing', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.CALL_VERIFIED,
        selfie_photo_url: 'p/selfie.jpg',
        qualification_document_url: 'p/q.jpg',
        aadhaar_document_url: null,
      });
      await expect(service.submitAdvancedDetails('user-1', validDto)).rejects.toMatchObject({
        code: 'PROFILE_017',
      });
    });

    it('succeeds with only aadhaar uploaded — qualification document is optional', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.CALL_VERIFIED,
        selfie_photo_url: 'p/selfie.jpg',
        qualification_document_url: null,
        aadhaar_document_url: 'p/aadhaar.jpg',
      });
      const result = await service.submitAdvancedDetails('user-1', validDto);
      expect(result.verification_status).toBe('pending_verification');
    });

    it('replaces preferred_cities with whatever was submitted, defaulting to empty when omitted', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.CALL_VERIFIED,
        selfie_photo_url: 'p/selfie.jpg',
        aadhaar_document_url: 'p/a.jpg',
      });
      await service.submitAdvancedDetails('user-1', {
        ...validDto,
        preferred_cities: ['bangalore', 'pune'] as any,
      });
      expect(preferredCitiesRepo.replaceForProfile).toHaveBeenCalledWith('profile-1', [
        'bangalore',
        'pune',
      ]);

      preferredCitiesRepo.replaceForProfile.mockClear();
      await service.submitAdvancedDetails('user-1', validDto);
      expect(preferredCitiesRepo.replaceForProfile).toHaveBeenCalledWith('profile-1', []);
    });

    it("succeeds without father's name or phone — they are optional", async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.CALL_VERIFIED,
        selfie_photo_url: 'p/selfie.jpg',
        qualification_document_url: 'p/q.jpg',
        aadhaar_document_url: 'p/a.jpg',
      });
      const { father_name, father_phone, ...dtoWithoutParents } = validDto;
      const result = await service.submitAdvancedDetails('user-1', dtoWithoutParents as any);
      expect(result.verification_status).toBe('pending_verification');
      expect(profilesRepo.updateAdvanced).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          father_name: null,
          father_phone: null,
        }),
      );
    });

    it('succeeds when current_address is omitted', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.CALL_VERIFIED,
        selfie_photo_url: 'p/selfie.jpg',
        qualification_document_url: 'p/q.jpg',
        aadhaar_document_url: 'p/a.jpg',
      });
      const { current_address, ...dtoWithoutAddress } = validDto;
      const result = await service.submitAdvancedDetails('user-1', dtoWithoutAddress as any);
      expect(result.verification_status).toBe('pending_verification');
      expect(profilesRepo.updateAdvanced).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ current_address: null }),
      );
    });

    it('succeeds for a rejected caregiver resubmitting, transitions to pending_verification', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.REJECTED,
        selfie_photo_url: 'p/selfie.jpg',
        qualification_document_url: 'p/q.jpg',
        aadhaar_document_url: 'p/a.jpg',
      });

      const result = await service.submitAdvancedDetails('user-1', validDto);
      expect(result).toEqual({
        message: 'Advanced details submitted',
        verification_status: 'pending_verification',
      });
      expect(usersRepo.updateCodeHash).not.toHaveBeenCalled();
      expect(profilesRepo.updateAdvanced).toHaveBeenCalled();
      expect(emailService.sendToAdmin).toHaveBeenCalledWith(
        expect.stringContaining('Advanced details'),
        expect.stringContaining('Test Caregiver'),
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'advanced_details_submitted',
          entityType: 'caregiver_profiles',
          entityId: 'profile-1',
        }),
      );
    });
  });

  describe('uploadSelfie', () => {
    it('throws UPLOAD_001 when no file is provided', async () => {
      await expect(service.uploadSelfie('user-1', undefined)).rejects.toMatchObject({
        code: 'UPLOAD_001',
      });
    });

    it('uploads to the correct path and updates the profile', async () => {
      profilesRepo.findByUserId.mockResolvedValue(shortProfile);
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
  });

  describe('uploadDocument', () => {
    const file = { originalname: 'doc.pdf', buffer: Buffer.from('x'), mimetype: 'application/pdf' } as any;

    beforeEach(() => {
      profilesRepo.findByUserId.mockResolvedValue(shortProfile);
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
      profilesRepo.findByUserId.mockResolvedValue({
        ...shortProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      await service.uploadDocument('user-1', { document_type: 'aadhaar' as any }, file);
      expect(profilesRepo.markForReReview).toHaveBeenCalledWith('profile-1');
    });

    it('re-uploading aadhaar on a pending_verification profile does not touch status', async () => {
      profilesRepo.findByUserId.mockResolvedValue(shortProfile); // pending_call
      await service.uploadDocument('user-1', { document_type: 'aadhaar' as any }, file);
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
    });

    it('re-uploading qualification never triggers review, even when available', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        ...shortProfile,
        verification_status: VerificationStatus.AVAILABLE,
      });
      await service.uploadDocument('user-1', { document_type: 'qualification' as any }, file);
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
    });
  });

  describe('updatePhone', () => {
    it('throws AUTH_001 when the phone is already registered to someone else', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile);
      usersRepo.findByPhone.mockResolvedValue({ id: 'someone-else' });
      await expect(
        service.updatePhone('user-1', { phone: '+919999999999' }),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
    });

    it('no-ops (still succeeds) when the phone is unchanged', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue(fullProfile);
      const result = await service.updatePhone('user-1', { phone: fullProfile.phone });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
      expect(usersRepo.findByPhone).not.toHaveBeenCalled();
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
      expect(result.verification_status).toBe('pending_verification');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'phone_changed' }),
      );
    });

    it('updates the phone without touching status when not available/unavailable', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        verification_status: VerificationStatus.IN_PROCESS,
      });
      const result = await service.updatePhone('user-1', { phone: '+919999999999' });
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(result.verification_status).toBe('in_process');
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

  describe('editAdvancedProfile', () => {
    it('throws PROFILE_025 when advanced details were never submitted', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        advanced_details_completed: false,
      });
      await expect(
        service.editAdvancedProfile('user-1', { current_address: '456 New St' }),
      ).rejects.toMatchObject({ code: 'PROFILE_025' });
    });

    it('writes only the provided fields and never touches verification_status', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        advanced_details_completed: true,
        current_address: '123 Old St',
        verification_status: VerificationStatus.AVAILABLE,
      });
      const result = await service.editAdvancedProfile('user-1', { current_address: '456 New St' });
      expect(profilesRepo.editAdvancedFields).toHaveBeenCalledWith('profile-1', {
        highest_qualification: undefined,
        father_name: undefined,
        father_phone: undefined,
        current_address: '456 New St',
        notes: undefined,
      });
      expect(profilesRepo.markForReReview).not.toHaveBeenCalled();
      expect(result).toEqual({ message: 'Profile updated', has_pending_edits: true });
    });

    it('does not write or email/audit-log when the given value matches the current one', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        advanced_details_completed: true,
        current_address: '123 Same St',
      });
      await service.editAdvancedProfile('user-1', { current_address: '123 Same St' });
      expect(profilesRepo.editAdvancedFields).not.toHaveBeenCalled();
      expect(emailService.sendToAdmin).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('replaces preferred_cities and flags pending edits even when no scalar field changed', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        advanced_details_completed: true,
      });
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore']);

      const result = await service.editAdvancedProfile('user-1', {
        preferred_cities: ['mumbai', 'pune'] as any,
      });

      expect(preferredCitiesRepo.replaceForProfile).toHaveBeenCalledWith('profile-1', [
        'mumbai',
        'pune',
      ]);
      expect(profilesRepo.editAdvancedFields).not.toHaveBeenCalled();
      expect(profilesRepo.flagPendingEdits).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({ message: 'Profile updated', has_pending_edits: true });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          beforeValue: { preferred_cities: ['bangalore'] },
          afterValue: { preferred_cities: ['mumbai', 'pune'] },
        }),
      );
    });

    it('does not replace preferred_cities when the (order-insensitive) set is unchanged', async () => {
      profilesRepo.findFullByUserId.mockResolvedValue({
        ...fullProfile,
        advanced_details_completed: true,
      });
      preferredCitiesRepo.findByProfileId.mockResolvedValue(['bangalore', 'mumbai']);

      await service.editAdvancedProfile('user-1', { preferred_cities: ['mumbai', 'bangalore'] as any });

      expect(preferredCitiesRepo.replaceForProfile).not.toHaveBeenCalled();
      expect(profilesRepo.flagPendingEdits).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
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
        submitted_at: null,
        verified_at: null,
      });
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
