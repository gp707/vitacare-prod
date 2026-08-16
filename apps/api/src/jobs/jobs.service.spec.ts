import { JobsService } from './jobs.service';
import { VerificationStatus } from '@vitacare/shared-constants';

describe('JobsService', () => {
  let service: JobsService;
  let db: any;
  let jobsRepo: any;
  let jobApplicationsRepo: any;
  let careReceiversRepo: any;
  let profilesRepo: any;
  let adminCaregiversRepo: any;
  let auditService: any;
  let fcmService: any;

  const careReceiver = {
    id: 'cr-1',
    age: 72,
    gender: 'female',
    weight_kg: 58,
    mobility: 'walks_independently',
    communication: 'verbal',
    feeding_type: 'oral_independent',
    tube_feeding_needs_assistance: null,
    medical_assistance: [],
    has_medical_condition: false,
    medical_conditions: [],
    medical_info: null,
    toilet_assistance: ['others'],
    requires_vital_monitoring: false,
    vital_monitoring_types: [],
  };

  const job = {
    id: 'job-1',
    job_number: 42,
    care_receiver_id: 'cr-1',
    city: 'bangalore',
    area: 'Indiranagar',
    description: 'Need a caregiver',
    duty_type: 'live_in',
    frequency_of_care: 'daily',
    start_time: null,
    end_time: null,
    start_date: null,
    languages: ['hindi'],
    salary_monthly: 30000,
    preferred_gender: 'female',
    preferred_religion: null,
    status: 'active',
    posted_by: 'admin-1',
    posted_at: new Date(),
    created_at: new Date(),
    updated_at: new Date(),
  };

  beforeEach(() => {
    db = { withTransaction: jest.fn((fn: any) => fn({ query: jest.fn() })) };
    jobsRepo = {
      create: jest.fn().mockResolvedValue(job),
      update: jest.fn().mockResolvedValue(job),
      findById: jest.fn(),
      listForAdmin: jest.fn(),
      listActiveForCaregiver: jest.fn(),
      close: jest.fn(),
      reopen: jest.fn(),
    };
    jobApplicationsRepo = {
      upsert: jest.fn(),
      findById: jest.fn(),
      decide: jest.fn(),
      findByJobId: jest.fn(),
    };
    careReceiversRepo = {
      create: jest.fn().mockResolvedValue(careReceiver),
      update: jest.fn().mockResolvedValue(careReceiver),
      findById: jest.fn().mockResolvedValue(careReceiver),
    };
    profilesRepo = { findByUserId: jest.fn() };
    adminCaregiversRepo = { getDetailById: jest.fn(), updateStatus: jest.fn() };
    auditService = { log: jest.fn() };
    fcmService = { sendToAllCaregivers: jest.fn() };
    service = new JobsService(
      db,
      jobsRepo,
      jobApplicationsRepo,
      careReceiversRepo,
      profilesRepo,
      adminCaregiversRepo,
      auditService,
      fcmService,
    );
  });

  describe('createJob', () => {
    const dto = {
      care_receiver: {
        age: 72 as any,
        gender: 'female' as any,
        weight_kg: 58 as any,
        mobility: 'walks_independently' as any,
        communication: 'verbal' as any,
        feeding_type: 'oral_independent' as any,
        medical_assistance: [] as any,
        has_medical_condition: false,
        toilet_assistance: ['others'] as any,
        requires_vital_monitoring: false,
      },
      city: 'bangalore' as any,
      area: 'Indiranagar',
      description: 'Need a caregiver',
      duty_type: 'live_in' as any,
      frequency_of_care: 'daily' as any,
      languages: ['hindi'] as any,
      salary_monthly: 30000,
      preferred_gender: 'female' as any,
    };

    it('creates the care receiver + job in one transaction, broadcasts a push, and audit-logs it', async () => {
      const result = await service.createJob('admin-1', dto, '127.0.0.1');
      expect(result).toEqual(job);
      expect(db.withTransaction).toHaveBeenCalled();
      expect(careReceiversRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          age: 72,
          mobility: 'walks_independently',
          medical_assistance: ['medication_reminders'],
          toilet_assistance: ['others'],
        }),
        expect.anything(),
      );
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'New Job: Live-In Care in Bangalore',
        'Indiranagar, Bangalore | IMMEDIATELY APPLY',
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', action: 'job_posted', entityId: 'job-1' }),
      );
    });

    it('derives start/end time from duty_type instead of accepting them as input', async () => {
      await service.createJob('admin-1', { ...dto, duty_type: 'day_duty' as any }, null);
      expect(jobsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ start_time: '08:00', end_time: '20:00' }),
        expect.anything(),
      );

      await service.createJob('admin-1', { ...dto, duty_type: 'night_duty' as any }, null);
      expect(jobsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ start_time: '20:00', end_time: '08:00' }),
        expect.anything(),
      );

      await service.createJob('admin-1', { ...dto, duty_type: 'live_in' as any }, null);
      expect(jobsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ start_time: null, end_time: null }),
        expect.anything(),
      );
    });

    it('defaults every optional care-receiver field to a real, explicit value when omitted', async () => {
      const minimalDto = {
        ...dto,
        care_receiver: { age: 72, gender: 'female', weight_kg: 58 } as any,
      };
      await service.createJob('admin-1', minimalDto, null);
      expect(careReceiversRepo.create).toHaveBeenCalledWith(
        {
          age: 72,
          gender: 'female',
          weight_kg: 58,
          mobility: 'walks_independently',
          communication: 'verbal',
          feeding_type: 'oral_independent',
          tube_feeding_needs_assistance: null,
          medical_assistance: ['medication_reminders'],
          has_medical_condition: false,
          medical_conditions: [],
          medical_info: null,
          toilet_assistance: ['independent'],
          requires_vital_monitoring: false,
          vital_monitoring_types: [],
        },
        expect.anything(),
      );
    });
  });

  describe('updateJob', () => {
    const dto = {
      care_receiver: {
        age: 73 as any,
        gender: 'female' as any,
        weight_kg: 60 as any,
        mobility: 'walks_independently' as any,
        communication: 'verbal' as any,
        feeding_type: 'oral_independent' as any,
        medical_assistance: [] as any,
        has_medical_condition: false,
        toilet_assistance: ['others'] as any,
        requires_vital_monitoring: false,
      },
      city: 'bangalore' as any,
      area: 'Koramangala',
      description: 'Updated description',
      duty_type: 'day_duty' as any,
      frequency_of_care: 'daily' as any,
      languages: ['hindi', 'english'] as any,
      salary_monthly: 35000,
      preferred_gender: 'female' as any,
    };

    it('throws GEN_002 when the job does not exist', async () => {
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.updateJob('admin-1', 'missing', dto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('updates the care receiver and job in one transaction, audit-logs it, and does NOT resend a push for an already-active job', async () => {
      jobsRepo.findById.mockResolvedValue({ ...job, status: 'active' });
      jobsRepo.update.mockResolvedValue({ ...job, city: 'bangalore', duty_type: 'day_duty', area: 'Koramangala' });

      const result = await service.updateJob('admin-1', 'job-1', dto, '127.0.0.1');

      expect(db.withTransaction).toHaveBeenCalled();
      expect(careReceiversRepo.update).toHaveBeenCalledWith(
        'cr-1',
        expect.objectContaining({
          age: 73,
          mobility: 'walks_independently',
          medical_assistance: ['medication_reminders'],
          toilet_assistance: ['others'],
        }),
        expect.anything(),
      );
      expect(jobsRepo.update).toHaveBeenCalledWith(
        'job-1',
        expect.objectContaining({
          city: 'bangalore',
          area: 'Koramangala',
          duty_type: 'day_duty',
          start_time: '08:00',
          end_time: '20:00',
          status: undefined,
        }),
        expect.anything(),
      );
      expect(fcmService.sendToAllCaregivers).not.toHaveBeenCalled();
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', action: 'job_updated', entityId: 'job-1' }),
      );
      expect(result.area).toBe('Koramangala');
    });

    it('reposts (reopens + re-broadcasts) a closed job on edit', async () => {
      jobsRepo.findById.mockResolvedValue({ ...job, status: 'closed' });
      jobsRepo.update.mockResolvedValue({ ...job, status: 'active', duty_type: 'day_duty', area: 'Koramangala' });

      await service.updateJob('admin-1', 'job-1', dto, null);

      expect(jobsRepo.update).toHaveBeenCalledWith(
        'job-1',
        expect.objectContaining({ status: 'active' }),
        expect.anything(),
      );
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalledWith(
        'New Job: Day Duty in Bangalore',
        'Koramangala, Bangalore | IMMEDIATELY APPLY',
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

    it('returns the job with its care receiver and applications', async () => {
      jobsRepo.findById.mockResolvedValue(job);
      jobApplicationsRepo.findByJobId.mockResolvedValue([{ id: 'app-1', status: 'applied' }]);
      const result = await service.getJobDetailForAdmin('job-1');
      expect(result).toEqual({
        ...job,
        care_receiver: careReceiver,
        applications: [{ id: 'app-1', status: 'applied' }],
      });
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
        'Reminder: Live-In Care in Bangalore',
        "Indiranagar, Bangalore | APPLY NOW BEFORE IT'S FILLED",
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
        items: [{ ...job, my_application_status: null }],
        total: 1,
      });
      const result = await service.listActiveJobsForCaregiver('user-1', { page: 1, limit: 20 } as any);
      expect(result.data).toEqual([{ ...job, my_application_status: null }]);
      expect(result.meta).toEqual({ page: 1, limit: 20, total: 1, totalPages: 1 });
    });
  });

  describe('applyToJob', () => {
    const dto = { status: 'applied' as any };

    it('throws PROFILE_019 when no profile exists', async () => {
      profilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.applyToJob('user-1', 'job-1', dto, null)).rejects.toMatchObject({
        code: 'PROFILE_019',
      });
    });

    it.each([
      VerificationStatus.PENDING_CALL,
      VerificationStatus.UNAVAILABLE,
      VerificationStatus.REJECTED,
    ])('throws JOB_001 when caregiver status is %s', async (status) => {
      profilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: status });
      await expect(service.applyToJob('user-1', 'job-1', dto, null)).rejects.toMatchObject({
        code: 'JOB_001',
      });
    });

    it.each([VerificationStatus.AVAILABLE, VerificationStatus.ASSIGNED])(
      'allows applying when caregiver status is %s',
      async (status) => {
        profilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: status });
        jobsRepo.findById.mockResolvedValue(job);
        jobApplicationsRepo.upsert.mockResolvedValue({ id: 'app-1', status: 'applied' });
        const result = await service.applyToJob('user-1', 'job-1', dto, null);
        expect(result).toEqual({ message: 'Application recorded', status: 'applied' });
      },
    );

    it('throws GEN_002 when the job does not exist', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(null);
      await expect(service.applyToJob('user-1', 'missing', dto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_002 when the job is closed', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue({ ...job, status: 'closed' });
      await expect(service.applyToJob('user-1', 'job-1', dto, null)).rejects.toMatchObject({
        code: 'JOB_002',
      });
    });

    it('upserts rejected status too (caregiver declining)', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(job);
      jobApplicationsRepo.upsert.mockResolvedValue({ id: 'app-1', status: 'rejected' });
      const result = await service.applyToJob('user-1', 'job-1', { status: 'rejected' as any }, null);
      expect(jobApplicationsRepo.upsert).toHaveBeenCalledWith('job-1', 'profile-1', 'rejected');
      expect(result).toEqual({ message: 'Application recorded', status: 'rejected' });
    });

    it('audit-logs the application', async () => {
      profilesRepo.findByUserId.mockResolvedValue({
        id: 'profile-1',
        verification_status: VerificationStatus.AVAILABLE,
      });
      jobsRepo.findById.mockResolvedValue(job);
      jobApplicationsRepo.upsert.mockResolvedValue({ id: 'app-1', status: 'applied' });
      await service.applyToJob('user-1', 'job-1', dto, '127.0.0.1');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'job_response',
          entityType: 'job_applications',
          entityId: 'app-1',
          ipAddress: '127.0.0.1',
        }),
      );
    });
  });

  describe('decideApplication', () => {
    const application = {
      id: 'app-1',
      job_id: 'job-1',
      profile_id: 'profile-1',
      status: 'applied',
      decided_by: null,
    };
    const caregiverDetail = { user_id: 'user-1' };

    it('throws JOB_006 when the application does not exist', async () => {
      jobApplicationsRepo.findById.mockResolvedValue(null);
      await expect(
        service.decideApplication('admin-1', 'job-1', 'missing', { status: 'accepted' as any }, null),
      ).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('throws JOB_006 when the application belongs to a different job', async () => {
      jobApplicationsRepo.findById.mockResolvedValue({ ...application, job_id: 'other-job' });
      await expect(
        service.decideApplication('admin-1', 'job-1', 'app-1', { status: 'accepted' as any }, null),
      ).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('accepts an applied application: closes the job and assigns the caregiver', async () => {
      jobApplicationsRepo.findById.mockResolvedValue(application);
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      const result = await service.decideApplication(
        'admin-1',
        'job-1',
        'app-1',
        { status: 'accepted' as any },
        null,
      );

      expect(jobApplicationsRepo.decide).toHaveBeenCalledWith('app-1', 'accepted', 'admin-1', expect.anything());
      expect(jobsRepo.close).toHaveBeenCalledWith('job-1', expect.anything());
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith(
        'profile-1',
        'assigned',
        null,
        'admin-1',
        expect.anything(),
      );
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'job_application_decided',
          targetUserId: 'user-1',
          afterValue: expect.objectContaining({ status: 'accepted', job_status: 'closed', caregiver_status: 'assigned' }),
        }),
      );
    });

    it('rejects a still-applied application with no job/caregiver side effects', async () => {
      jobApplicationsRepo.findById.mockResolvedValue(application);
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      await service.decideApplication('admin-1', 'job-1', 'app-1', { status: 'rejected' as any }, null);

      expect(jobApplicationsRepo.decide).toHaveBeenCalledWith('app-1', 'rejected', 'admin-1', expect.anything());
      expect(jobsRepo.close).not.toHaveBeenCalled();
      expect(jobsRepo.reopen).not.toHaveBeenCalled();
      expect(adminCaregiversRepo.updateStatus).not.toHaveBeenCalled();
    });

    it('rejecting a previously-accepted application reopens the job and un-assigns the caregiver', async () => {
      jobApplicationsRepo.findById.mockResolvedValue({ ...application, status: 'accepted' });
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      await service.decideApplication('admin-1', 'job-1', 'app-1', { status: 'rejected' as any }, null);

      expect(jobApplicationsRepo.decide).toHaveBeenCalledWith('app-1', 'rejected', 'admin-1', expect.anything());
      expect(jobsRepo.reopen).toHaveBeenCalledWith('job-1', expect.anything());
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith(
        'profile-1',
        'available',
        null,
        'admin-1',
        expect.anything(),
      );
    });

    it('throws JOB_007 when accepting an already-accepted application', async () => {
      jobApplicationsRepo.findById.mockResolvedValue({ ...application, status: 'accepted' });
      await expect(
        service.decideApplication('admin-1', 'job-1', 'app-1', { status: 'accepted' as any }, null),
      ).rejects.toMatchObject({ code: 'JOB_007' });
    });

    it('throws JOB_007 when deciding an already-rejected application', async () => {
      jobApplicationsRepo.findById.mockResolvedValue({ ...application, status: 'rejected' });
      await expect(
        service.decideApplication('admin-1', 'job-1', 'app-1', { status: 'rejected' as any }, null),
      ).rejects.toMatchObject({ code: 'JOB_007' });
      await expect(
        service.decideApplication('admin-1', 'job-1', 'app-1', { status: 'accepted' as any }, null),
      ).rejects.toMatchObject({ code: 'JOB_007' });
    });
  });
});
