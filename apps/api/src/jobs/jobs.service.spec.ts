import { JobsService } from './jobs.service';
import { VerificationStatus } from '@vitacare/shared-constants';

describe('JobsService', () => {
  let service: JobsService;
  let jobsRepo: any;
  let jobResponsesRepo: any;
  let profilesRepo: any;
  let auditService: any;
  let fcmService: any;

  const job = {
    id: 'job-1',
    work_type: 'bedside_care',
    city: 'bangalore',
    description: 'Need a bedside caregiver',
    duty_timings: '24hrs_live_in',
    language: 'hindi',
    gender_needed: 'female',
    religion: 'hindu',
    status: 'active',
    posted_by: 'admin-1',
    created_at: new Date(),
    updated_at: new Date(),
  };

  beforeEach(() => {
    jobsRepo = {
      create: jest.fn().mockResolvedValue(job),
      findById: jest.fn(),
      listForAdmin: jest.fn(),
      listActiveForCaregiver: jest.fn(),
      close: jest.fn(),
    };
    jobResponsesRepo = {
      upsert: jest.fn(),
      findByJobId: jest.fn(),
    };
    profilesRepo = { findByUserId: jest.fn() };
    auditService = { log: jest.fn() };
    fcmService = { sendToAllCaregivers: jest.fn() };
    service = new JobsService(jobsRepo, jobResponsesRepo, profilesRepo, auditService, fcmService);
  });

  describe('createJob', () => {
    const dto = {
      work_type: 'bedside_care' as any,
      city: 'bangalore' as any,
      description: 'Need a bedside caregiver',
      duty_timings: '24hrs_live_in' as any,
      language: 'hindi' as any,
      gender_needed: 'female' as any,
      religion: 'hindu' as any,
    };

    it('creates the job, broadcasts a push matching SPEC.md 6.7 exactly, and audit-logs it', async () => {
      const result = await service.createJob('admin-1', dto, '127.0.0.1');
      expect(result).toEqual(job);
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'New Job: Bedside Care - ₹28,000–₹35,000',
        'Bangalore | 24Hrs (Live-In) | IMMEDIATELY APPLY',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', action: 'job_posted', entityId: 'job-1' }),
      );
    });
  });

  describe('listJobsForAdmin', () => {
    it('paginates and shapes meta correctly', async () => {
      jobsRepo.listForAdmin.mockResolvedValue({ items: [job], total: 25 });
      const result = await service.listJobsForAdmin({ page: 2, limit: 10 } as any);
      expect(result.data).toEqual([job]);
      expect(result.meta).toEqual({ page: 2, limit: 10, total: 25, totalPages: 3 });
    });
  });

  describe('getJobDetailForAdmin', () => {
    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.getJobDetailForAdmin('missing')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns the job with its responses', async () => {
      jobsRepo.findById.mockResolvedValue(job);
      jobResponsesRepo.findByJobId.mockResolvedValue([{ id: 'resp-1', response: 'accepted' }]);
      const result = await service.getJobDetailForAdmin('job-1');
      expect(result).toEqual({ ...job, responses: [{ id: 'resp-1', response: 'accepted' }] });
    });
  });

  describe('closeJob', () => {
    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.closeJob('admin-1', 'missing', null)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('closes the job and audit-logs it', async () => {
      jobsRepo.findById.mockResolvedValue(job);
      const result = await service.closeJob('admin-1', 'job-1', null);
      expect(jobsRepo.close).toHaveBeenCalledWith('job-1');
      expect(result).toEqual({ message: 'Job closed', status: 'closed' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'job_closed', entityId: 'job-1' }),
      );
    });
  });

  describe('sendReminder', () => {
    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.sendReminder('admin-1', 'missing', null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_005 when the job is closed', async () => {
      jobsRepo.findById.mockResolvedValue({ ...job, status: 'closed' });
      await expect(service.sendReminder('admin-1', 'job-1', null)).rejects.toMatchObject({
        code: 'JOB_005',
      });
      expect(fcmService.sendToAllCaregivers).not.toHaveBeenCalled();
    });

    it('broadcasts a reminder push and audit-logs it', async () => {
      jobsRepo.findById.mockResolvedValue(job);
      const result = await service.sendReminder('admin-1', 'job-1', '127.0.0.1');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'Reminder: Bedside Care - ₹28,000–₹35,000',
        "Bangalore | 24Hrs (Live-In) | APPLY NOW BEFORE IT'S FILLED",
      );
      expect(result).toEqual({ message: 'Reminder sent' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          action: 'job_reminder_sent',
          entityId: 'job-1',
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });

  describe('listActiveJobsForCaregiver', () => {
    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findByUserId.mockResolvedValue(null);
      await expect(
        service.listActiveJobsForCaregiver('user-1', { page: 1, limit: 20 } as any),
      ).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('returns active jobs with pagination meta', async () => {
      profilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      jobsRepo.listActiveForCaregiver.mockResolvedValue({
        items: [{ ...job, my_response: null }],
        total: 1,
      });
      const result = await service.listActiveJobsForCaregiver('user-1', { page: 1, limit: 20 } as any);
      expect(result.data).toEqual([{ ...job, my_response: null }]);
      expect(result.meta).toEqual({ page: 1, limit: 20, total: 1, totalPages: 1 });
    });
  });

  describe('respondToJob', () => {
    const dto = { response: 'accepted' as any };

    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.respondToJob('user-1', 'job-1', dto, null)).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it.each([
      VerificationStatus.PENDING_CALL,
      VerificationStatus.CALL_VERIFIED,
      VerificationStatus.PENDING_VERIFICATION,
      VerificationStatus.IN_PROCESS,
      VerificationStatus.UNAVAILABLE,
      VerificationStatus.REJECTED,
    ])('throws JOB_001 when caregiver status is %s', async (status) => {
      profilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: status });
      await expect(service.respondToJob('user-1', 'job-1', dto, null)).rejects.toMatchObject({
        code: 'JOB_001',
      });
    });

    it.each([VerificationStatus.AVAILABLE, VerificationStatus.ASSIGNED])(
      'allows responding when caregiver status is %s',
      async (status) => {
        profilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: status });
        jobsRepo.findById.mockResolvedValue(job);
        jobResponsesRepo.upsert.mockResolvedValue({ id: 'resp-1', response: 'accepted' });
        const result = await service.respondToJob('user-1', 'job-1', dto, null);
        expect(result).toEqual({ message: 'Response recorded', response: 'accepted' });
      },
    );

    it('throws GEN_002 when the job does not exist', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.respondToJob('user-1', 'missing', dto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_002 when the job is closed', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue({ ...job, status: 'closed' });
      await expect(service.respondToJob('user-1', 'job-1', dto, null)).rejects.toMatchObject({
        code: 'JOB_002',
      });
    });

    it('stores the message when asking for more details', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(job);
      jobResponsesRepo.upsert.mockResolvedValue({ id: 'resp-1', response: 'more_details' });
      await service.respondToJob(
        'user-1',
        'job-1',
        { response: 'more_details' as any, message: 'What are the exact hours?' },
        null,
      );
      expect(jobResponsesRepo.upsert).toHaveBeenCalledWith(
        'job-1',
        'profile-1',
        'more_details',
        'What are the exact hours?',
      );
    });

    it('drops any message when the response is not more_details', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(job);
      jobResponsesRepo.upsert.mockResolvedValue({ id: 'resp-1', response: 'accepted' });
      await service.respondToJob(
        'user-1',
        'job-1',
        { response: 'accepted' as any, message: 'irrelevant stray message' },
        null,
      );
      expect(jobResponsesRepo.upsert).toHaveBeenCalledWith('job-1', 'profile-1', 'accepted', null);
    });

    it('audit-logs the response', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(job);
      jobResponsesRepo.upsert.mockResolvedValue({ id: 'resp-1', response: 'accepted' });
      await service.respondToJob('user-1', 'job-1', dto, '127.0.0.1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'job_response',
          entityType: 'job_responses',
          entityId: 'resp-1',
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });
});
