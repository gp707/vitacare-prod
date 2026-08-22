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
  let adminCaregiversRepo: any;

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
      update: jest.fn(),
      cancel: jest.fn(),
    };
    jobApplicationsRepo = {
      findByJobId: jest.fn(),
      findById: jest.fn(),
      hasActiveApplicationForJob: jest.fn().mockResolvedValue(false),
      findActiveForJob: jest.fn().mockResolvedValue([]),
      decide: jest.fn(),
    };
    careReceiversRepo = {
      create: jest.fn().mockResolvedValue({ id: 'cr-1' }),
      update: jest.fn(),
      findById: jest.fn(),
    };
    individualProfilesRepo = { findByUserId: jest.fn() };
    usersRepo = {
      findById: jest.fn(),
      findByPhoneAndRoles: jest.fn(),
      updatePhone: jest.fn(),
      updateCodeHash: jest.fn(),
    };
    jobsService = { decideApplication: jest.fn() };
    auditService = { log: jest.fn() };
    caregiverService = { getApplicantProfile: jest.fn() };
    adminCaregiversRepo = { updateStatus: jest.fn() };

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
      adminCaregiversRepo,
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
          posted_by_role: 'individual',
        }),
        client,
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'job_posted', entityId: 'job-1' }),
      );
      expect(result.id).toBe('job-1');
    });
  });

  describe('editRequirement', () => {
    const editDto = {
      care_receiver: careReceiverDto,
      city: 'bangalore',
      area: 'Koramangala',
      duty_type: 'day_duty',
      start_date: '2026-09-15',
      languages: ['hindi', 'english'],
    } as any;

    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.editRequirement('user-1', 'job-1', editDto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws GEN_002 when the job belongs to someone else', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'someone-else' });
      await expect(service.editRequirement('user-1', 'job-1', editDto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_014 when there is an active (applied/accepted) application', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', status: 'active' });
      jobApplicationsRepo.hasActiveApplicationForJob.mockResolvedValue(true);
      await expect(service.editRequirement('user-1', 'job-1', editDto, null)).rejects.toMatchObject({
        code: 'JOB_014',
      });
    });

    it('throws JOB_013 when trying to set salary/frequency before the requirement has ever been reviewed', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'pending_review',
        frequency_of_care: null,
      });
      await expect(
        service.editRequirement(
          'user-1',
          'job-1',
          { ...editDto, frequency_of_care: 'daily', salary_amount: 30000 },
          null,
        ),
      ).rejects.toMatchObject({ code: 'JOB_013' });
    });

    it('edits a still-pending_review requirement, leaving frequency_of_care/salary_amount null and status untouched', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'pending_review',
        duty_type: 'live_in',
        city: 'bangalore',
        care_receiver_id: 'cr-1',
        frequency_of_care: null,
      });
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));
      jobsRepo.update.mockResolvedValue({ id: 'job-1', duty_type: 'day_duty', city: 'bangalore', status: 'pending_review' });

      await service.editRequirement('user-1', 'job-1', editDto, '127.0.0.1');

      expect(careReceiversRepo.update).toHaveBeenCalledWith(
        'cr-1',
        expect.objectContaining({ age: 70, gender: 'female', weight_kg: 55 }),
        client,
      );
      const [, updateInput] = jobsRepo.update.mock.calls[0];
      expect(updateInput).toEqual(
        expect.objectContaining({
          city: 'bangalore',
          area: 'Koramangala',
          duty_type: 'day_duty',
          frequency_of_care: null,
          salary_amount: null,
        }),
      );
      expect(updateInput).not.toHaveProperty('status');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'job_updated', entityId: 'job-1' }),
      );
    });

    it('allows editing salary/frequency once the requirement has already been reviewed once, without changing status', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'closed',
        duty_type: 'live_in',
        city: 'bangalore',
        care_receiver_id: 'cr-1',
        frequency_of_care: 'monthly',
        salary_amount: 25000,
      });
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));
      jobsRepo.update.mockResolvedValue({ id: 'job-1', duty_type: 'day_duty', city: 'bangalore', status: 'closed' });

      await service.editRequirement(
        'user-1',
        'job-1',
        { ...editDto, frequency_of_care: 'daily', salary_amount: 1500 },
        null,
      );

      const [, updateInput] = jobsRepo.update.mock.calls[0];
      expect(updateInput).toEqual(
        expect.objectContaining({ frequency_of_care: 'daily', salary_amount: 1500 }),
      );
      expect(updateInput).not.toHaveProperty('status');
    });

    it('keeps the existing salary/frequency when already reviewed but the edit omits them', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'active',
        duty_type: 'live_in',
        city: 'bangalore',
        care_receiver_id: 'cr-1',
        frequency_of_care: 'monthly',
        salary_amount: 25000,
      });
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));
      jobsRepo.update.mockResolvedValue({ id: 'job-1', duty_type: 'day_duty', city: 'bangalore', status: 'active' });

      await service.editRequirement('user-1', 'job-1', editDto, null);

      const [, updateInput] = jobsRepo.update.mock.calls[0];
      expect(updateInput).toEqual(
        expect.objectContaining({ frequency_of_care: 'monthly', salary_amount: 25000 }),
      );
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
      usersRepo.findByPhoneAndRoles.mockResolvedValue({ id: 'someone-else' });
      await expect(
        service.updatePhone('user-1', { phone: '+919876500000' } as any, null),
      ).rejects.toMatchObject({ code: 'AUTH_001' });
      expect(usersRepo.updatePhone).not.toHaveBeenCalled();
    });

    it('updates the phone and audit-logs it when it is new and unused', async () => {
      individualProfilesRepo.findByUserId.mockResolvedValue({ id: 'ip-1' });
      usersRepo.findById.mockResolvedValue({ id: 'user-1', phone: '+919876543210' });
      usersRepo.findByPhoneAndRoles.mockResolvedValue(null);

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
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', cancelled_at: null });
      jobApplicationsRepo.findByJobId.mockResolvedValue([{ id: 'app-1' }]);
      const result = await service.getMyRequirementApplications('user-1', 'job-1');
      expect(result).toEqual([{ id: 'app-1' }]);
    });

    it('returns an empty list once the requirement has been cancelled, without querying applications', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', cancelled_at: new Date() });
      const result = await service.getMyRequirementApplications('user-1', 'job-1');
      expect(result).toEqual([]);
      expect(jobApplicationsRepo.findByJobId).not.toHaveBeenCalled();
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
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', cancelled_at: null });
      jobApplicationsRepo.findById.mockResolvedValue({ id: 'app-1', job_id: 'job-1', profile_id: 'profile-1' });
      caregiverService.getApplicantProfile.mockResolvedValue({ full_name: 'Nurse Nita' });
      const result = await service.getApplicantProfile('user-1', 'job-1', 'app-1');
      expect(caregiverService.getApplicantProfile).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({ full_name: 'Nurse Nita' });
    });

    it('throws GEN_002 once the requirement has been cancelled, without looking up the application', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', cancelled_at: new Date() });
      await expect(service.getApplicantProfile('user-1', 'job-1', 'app-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(jobApplicationsRepo.findById).not.toHaveBeenCalled();
      expect(caregiverService.getApplicantProfile).not.toHaveBeenCalled();
    });
  });

  describe('cancelRequirement', () => {
    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.cancelRequirement('user-1', 'job-1', null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws GEN_002 when the job belongs to someone else', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'someone-else', status: 'active' });
      await expect(service.cancelRequirement('user-1', 'job-1', null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_015 when the requirement was already cancelled', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'closed',
        cancelled_at: new Date(),
        rejection_reason: null,
      });
      await expect(service.cancelRequirement('user-1', 'job-1', null)).rejects.toMatchObject({
        code: 'JOB_015',
      });
    });

    it('throws JOB_015 when the requirement was already admin-rejected', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'closed',
        cancelled_at: null,
        rejection_reason: 'Not a good fit for the program',
      });
      await expect(service.cancelRequirement('user-1', 'job-1', null)).rejects.toMatchObject({
        code: 'JOB_015',
      });
    });

    it('allows cancelling an already-closed requirement that has a filled/accepted candidate', async () => {
      jobsRepo.findById.mockResolvedValue({
        id: 'job-1',
        posted_by: 'user-1',
        status: 'closed',
        cancelled_at: null,
        rejection_reason: null,
      });
      jobApplicationsRepo.findActiveForJob.mockResolvedValue([
        { id: 'app-1', status: 'accepted', profile_id: 'profile-1' },
      ]);
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));

      const result = await service.cancelRequirement('user-1', 'job-1', null);

      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith(
        'profile-1',
        'available',
        null,
        'user-1',
        client,
      );
      expect(jobsRepo.cancel).toHaveBeenCalledWith('job-1', client);
      expect(result.rejected_applications).toBe(1);
    });

    it('cancels a pending_review requirement with no applications — no cascading side effects', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', status: 'pending_review' });
      jobApplicationsRepo.findActiveForJob.mockResolvedValue([]);
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));

      const result = await service.cancelRequirement('user-1', 'job-1', '127.0.0.1');

      expect(jobApplicationsRepo.decide).not.toHaveBeenCalled();
      expect(adminCaregiversRepo.updateStatus).not.toHaveBeenCalled();
      expect(jobsRepo.cancel).toHaveBeenCalledWith('job-1', client);
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-1', action: 'job_closed', entityId: 'job-1' }),
      );
      expect(result).toEqual({ message: 'Requirement cancelled', status: 'closed', rejected_applications: 0 });
    });

    it('rejects every applied/accepted application with a fixed reason and flips an accepted caregiver back to available', async () => {
      jobsRepo.findById.mockResolvedValue({ id: 'job-1', posted_by: 'user-1', status: 'active' });
      jobApplicationsRepo.findActiveForJob.mockResolvedValue([
        { id: 'app-1', status: 'applied', profile_id: 'profile-1' },
        { id: 'app-2', status: 'accepted', profile_id: 'profile-2' },
      ]);
      const client = {};
      db.withTransaction.mockImplementation(async (fn: any) => fn(client));

      const result = await service.cancelRequirement('user-1', 'job-1', null);

      expect(jobApplicationsRepo.decide).toHaveBeenCalledWith(
        'app-1',
        'rejected',
        'user-1',
        client,
        'This requirement was cancelled.',
      );
      expect(jobApplicationsRepo.decide).toHaveBeenCalledWith(
        'app-2',
        'rejected',
        'user-1',
        client,
        'This requirement was cancelled.',
      );
      // Only the accepted applicant is flipped back to available — the
      // still-applied one was never assigned in the first place.
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledTimes(1);
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith(
        'profile-2',
        'available',
        null,
        'user-1',
        client,
      );
      expect(jobsRepo.cancel).toHaveBeenCalledWith('job-1', client);
      expect(result.rejected_applications).toBe(2);
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
