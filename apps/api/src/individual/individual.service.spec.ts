import { IndividualService } from './individual.service';

describe('IndividualService', () => {
  let service: IndividualService;
  let db: any;
  let jobsRepo: any;
  let jobApplicationsRepo: any;
  let careReceiversRepo: any;
  let individualProfilesRepo: any;
  let usersRepo: any;
  let jobsService: any;
  let auditService: any;
  let caregiverService: any;

  const careReceiverDto = {
    age: 70,
    gender: 'female',
    weight_kg: 55,
  };

  const dto = {
    care_receiver: careReceiverDto,
    city: 'bangalore',
    area: 'Indiranagar',
    duty_type: 'live_in',
    start_date: '2026-09-01',
    languages: ['hindi'],
  } as any;

  beforeEach(() => {
    db = { withTransaction: jest.fn() };
    jobsRepo = {
      create: jest.fn(),
      findById: jest.fn(),
      listByPostedBy: jest.fn(),
      findLiveByPostedBy: jest.fn(),
    };
    jobApplicationsRepo = { findByJobId: jest.fn(), findById: jest.fn() };
    careReceiversRepo = { create: jest.fn().mockResolvedValue({ id: 'cr-1' }), findById: jest.fn() };
    individualProfilesRepo = { findByUserId: jest.fn() };
    usersRepo = {
      findById: jest.fn(),
      findByPhone: jest.fn(),
      updatePhone: jest.fn(),
      updateCodeHash: jest.fn(),
    };
    jobsService = { decideApplication: jest.fn() };
    auditService = { log: jest.fn() };
    caregiverService = { getApplicantProfile: jest.fn() };

    service = new IndividualService(
      db,
      jobsRepo,
      jobApplicationsRepo,
      careReceiversRepo,
      individualProfilesRepo,
      usersRepo,
      jobsService,
      auditService,
      caregiverService,
    );
  });

  describe('getMe', () => {
    it('throws GEN_002 when the user does not exist', async () => {
      usersRepo.findById.mockResolvedValue(null);
      await expect(service.getMe('user-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns identity + job-posting-blocked state', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'user-1', full_name: 'Asha Patel', phone: '+919876543210' });
      individualProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: true });
      const result = await service.getMe('user-1');
      expect(result).toEqual({
        user_id: 'user-1',
        full_name: 'Asha Patel',
        phone: '+919876543210',
        is_job_posting_blocked: true,
      });
    });
  });

  describe('createRequirement', () => {
    it('throws GEN_002 when no individual profile exists', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.createRequirement('user-1', dto, null)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws JOB_010 when job posting is blocked', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: true });
      await expect(service.createRequirement('user-1', dto, null)).rejects.toMatchObject({ code: 'JOB_010' });
    });

    it('throws JOB_009 when a live requirement already exists', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      jobsRepo.findLiveByPostedBy.mockResolvedValue({ id: 'job-existing' });
      await expect(service.createRequirement('user-1', dto, null)).rejects.toMatchObject({ code: 'JOB_009' });
    });

    it('creates a pending_review job with null frequency_of_care/salary_amount, posted_by the caller', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      jobsRepo.findLiveByPostedBy.mockResolvedValue(null);
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));
      jobsRepo.create.mockResolvedValue({ id: 'job-1', duty_type: 'live_in', city: 'bangalore', status: 'pending_review' });

      const result = await service.createRequirement('user-1', dto, '127.0.0.1');

      expect(careReceiversRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ age: 70, gender: 'female', weight_kg: 55 }),
        client,
      );
      expect(jobsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          care_receiver_id: 'cr-1',
          posted_by: 'user-1',
          status: 'pending_review',
          frequency_of_care: null,
          salary_amount: null,
        }),
        client,
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'job_posted', entityId: 'job-1' }),
      );
      expect(result.id).toBe('job-1');
    });
  });

  describe('listMyRequirements', () => {
    it('joins each job with its own care_receiver', async () => {
      jobsRepo.listByPostedBy.mockResolvedValue([
        { id: 'job-1', care_receiver_id: 'cr-1' },
        { id: 'job-2', care_receiver_id: 'cr-2' },
      ]);
      careReceiversRepo.findById.mockImplementation((id: string) => Promise.resolve({ id, age: 70 }));

      const result = await service.listMyRequirements('user-1');

      expect(jobsRepo.listByPostedBy).toHaveBeenCalledWith('user-1');
      expect(careReceiversRepo.findById).toHaveBeenNthCalledWith(1, 'cr-1');
      expect(careReceiversRepo.findById).toHaveBeenNthCalledWith(2, 'cr-2');
      expect(result).toEqual([
        { id: 'job-1', care_receiver_id: 'cr-1', care_receiver: { id: 'cr-1', age: 70 } },
        { id: 'job-2', care_receiver_id: 'cr-2', care_receiver: { id: 'cr-2', age: 70 } },
      ]);
    });
  });

  describe('updatePhone', () => {
    it('throws GEN_002 when no individual profile exists', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(
        service.updatePhone('user-1', { phone: '+919876543210' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('is a no-op when the phone is unchanged', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ id: 'ip-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      const result = await service.updatePhone('user-1', { phone: '+919876543210' } as any, null);
      expect(result).toEqual({ message: 'Phone number updated' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('throws AUTH_001 when the new phone is already taken', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ id: 'ip-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      usersRepo.findByPhone.mockResolvedValue({ id: 'someone-else' });
      await expect(
        service.updatePhone('user-1', { phone: '+919876500000' } as any, null),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
    });

    it('updates the phone and audit-logs it when it is new and unused', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ id: 'ip-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      usersRepo.findByPhone.mockResolvedValue(null);

      const result = await service.updatePhone('user-1', { phone: '+919876500000' } as any, '127.0.0.1');

      expect(usersRepo.updatePhone).toHaveBeenCalledWith('user-1', '+919876500000');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'phone_changed',
          entityType: 'individual_profiles',
          entityId: 'ip-1',
        }),
      );
      expect(result).toEqual({ message: 'Phone number updated' });
    });
  });

  describe('updateCode', () => {
    it('throws GEN_002 when no individual profile exists', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.updateCode('user-1', { code: '1234' } as any, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('hashes and stores the new code, and audit-logs it', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ id: 'ip-1' });
      const result = await service.updateCode('user-1', { code: '4321' } as any, '127.0.0.1');

      expect(usersRepo.updateCodeHash).toHaveBeenCalledWith('user-1', expect.any(String));
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'code_changed', entityType: 'individual_profiles' }),
      );
      expect(result).toEqual({ message: 'Login code updated' });
    });
  });

  describe('getMyRequirementApplications', () => {
    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.getMyRequirementApplications('user-1', 'job-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it("throws GEN_002 when the job belongs to someone else (ownership check)", async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'someone-else' });
      await expect(service.getMyRequirementApplications('user-1', 'job-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('returns applications for a job the caller owns', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      jobApplicationsRepo.findByJobId.mockResolvedValue([{ id: 'app-1' }]);
      const result = await service.getMyRequirementApplications('user-1', 'job-1');
      expect(result).toEqual([{ id: 'app-1' }]);
    });
  });

  describe('getApplicantProfile', () => {
    it('throws GEN_002 when the job belongs to someone else', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'someone-else' });
      await expect(service.getApplicantProfile('user-1', 'job-1', 'app-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(caregiverService.getApplicantProfile).not.toHaveBeenCalled();
    });

    it('throws GEN_002 when the application does not belong to this job', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      jobApplicationsRepo.findById.mockResolvedValue({ id: 'app-1', job_id: 'some-other-job', profile_id: 'p-1' });
      await expect(service.getApplicantProfile('user-1', 'job-1', 'app-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(caregiverService.getApplicantProfile).not.toHaveBeenCalled();
    });

    it("delegates to CaregiverService.getApplicantProfile with the application's profile_id", async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      jobApplicationsRepo.findById.mockResolvedValue({ id: 'app-1', job_id: 'job-1', profile_id: 'profile-1' });
      caregiverService.getApplicantProfile.mockResolvedValue({ full_name: 'Nurse Nita' });
      const result = await service.getApplicantProfile('user-1', 'job-1', 'app-1');
      expect(caregiverService.getApplicantProfile).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({ full_name: 'Nurse Nita' });
    });
  });

  describe('decideMyApplication', () => {
    it('throws GEN_002 when the job belongs to someone else', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'someone-else' });
      await expect(
        service.decideMyApplication('user-1', 'job-1', 'app-1', { status: 'accepted' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
      expect(jobsService.decideApplication).not.toHaveBeenCalled();
    });

    it("delegates to JobsService.decideApplication (full reuse) when the caller owns the job", async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      jobsService.decideApplication.mockResolvedValue({ message: 'Application updated', status: 'accepted' });
      const dto2 = { status: 'accepted' } as any;
      const result = await service.decideMyApplication('user-1', 'job-1', 'app-1', dto2, '127.0.0.1');
      expect(jobsService.decideApplication).toHaveBeenCalledWith('user-1', 'job-1', 'app-1', dto2, '127.0.0.1');
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });

    it('throws JOB_012 when rejecting without a reason', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      await expect(
        service.decideMyApplication('user-1', 'job-1', 'app-1', { status: 'rejected' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_012' });
      expect(jobsService.decideApplication).not.toHaveBeenCalled();
    });

    it('throws JOB_012 when rejecting with a blank/whitespace-only reason', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      await expect(
        service.decideMyApplication('user-1', 'job-1', 'app-1', { status: 'rejected', reason: '   ' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_012' });
      expect(jobsService.decideApplication).not.toHaveBeenCalled();
    });

    it('accepting never requires a reason', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      jobsService.decideApplication.mockResolvedValue({ message: 'Application updated', status: 'accepted' });
      await service.decideMyApplication('user-1', 'job-1', 'app-1', { status: 'accepted' } as any, null);
      expect(jobsService.decideApplication).toHaveBeenCalled();
    });

    it('rejecting with a reason delegates through, reason intact', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1' });
      jobsService.decideApplication.mockResolvedValue({ message: 'Application updated', status: 'rejected' });
      const dto2 = { status: 'rejected', reason: 'Schedule does not match' } as any;
      await service.decideMyApplication('user-1', 'job-1', 'app-1', dto2, '127.0.0.1');
      expect(jobsService.decideApplication).toHaveBeenCalledWith('user-1', 'job-1', 'app-1', dto2, '127.0.0.1');
    });
  });
});
