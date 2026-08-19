import { OrganisationRequirementsService } from './organisation-requirements.service';

describe('OrganisationRequirementsService', () => {
  let service: OrganisationRequirementsService;
  let db: any;
  let requirementsRepo: any;
  let applicationsRepo: any;
  let caregiverProfilesRepo: any;
  let adminCaregiversRepo: any;
  let organisationProfilesRepo: any;
  let fcmService: any;
  let auditService: any;
  let caregiverService: any;

  const createDto = {
    type_of_nurse: 'registered_nurse',
    accommodation_provided: true,
    food_provided: false,
  } as any;

  beforeEach(() => {
    db = { withTransaction: jest.fn(async (fn: any) => fn({})) };
    requirementsRepo = {
      create: jest.fn(),
      findById: jest.fn(),
      listByPostedBy: jest.fn(),
      listActiveForCaregiver: jest.fn(),
      listForAdmin: jest.fn(),
      update: jest.fn(),
      reject: jest.fn(),
      close: jest.fn(),
      reopen: jest.fn(),
    };
    applicationsRepo = {
      findById: jest.fn(),
      findByRequirementId: jest.fn(),
      decide: jest.fn(),
      upsert: jest.fn(),
      findByRequirementAndProfile: jest.fn(),
      markCompleted: jest.fn(),
      countAcceptedByProfileId: jest.fn(),
      findAssignedByProfileId: jest.fn(),
    };
    caregiverProfilesRepo = { findByUserId: jest.fn(), markAvailable: jest.fn() };
    adminCaregiversRepo = { getDetailById: jest.fn(), updateStatus: jest.fn() };
    organisationProfilesRepo = { findByUserId: jest.fn() };
    fcmService = { sendToAllCaregivers: jest.fn() };
    auditService = { log: jest.fn() };
    caregiverService = { getApplicantProfile: jest.fn() };

    service = new OrganisationRequirementsService(
      db,
      requirementsRepo,
      applicationsRepo,
      caregiverProfilesRepo,
      adminCaregiversRepo,
      organisationProfilesRepo,
      fcmService,
      auditService,
      caregiverService,
    );
  });

  describe('createRequirement', () => {
    it('throws GEN_002 when no organisation profile exists', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.createRequirement('org-1', createDto, null)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws JOB_010 when job posting is blocked', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: true });
      await expect(service.createRequirement('org-1', createDto, null)).rejects.toMatchObject({ code: 'JOB_010' });
    });

    it('creates a pending_review requirement, posted_by the caller, no one-live limit check', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      requirementsRepo.create.mockResolvedValue({ id: 'req-1', type_of_nurse: 'registered_nurse', status: 'pending_review' });

      const result = await service.createRequirement('org-1', createDto, '127.0.0.1');

      expect(requirementsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ posted_by: 'org-1', status: 'pending_review', type_of_nurse: 'registered_nurse' }),
      );
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'org-1', action: 'org_requirement_posted', entityId: 'req-1' }),
      );
      expect(result.id).toBe('req-1');
    });
  });

  describe('listMyRequirements', () => {
    it('delegates to requirementsRepo.listByPostedBy (no live-limit — org can have many)', async () => {
      requirementsRepo.listByPostedBy.mockResolvedValue([{ id: 'req-1' }, { id: 'req-2' }]);
      const result = await service.listMyRequirements('org-1');
      expect(requirementsRepo.listByPostedBy).toHaveBeenCalledWith('org-1');
      expect(result).toHaveLength(2);
    });
  });

  describe('getRequirementApplications', () => {
    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.getRequirementApplications('org-1', 'req-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws GEN_002 when the requirement belongs to someone else', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'someone-else' });
      await expect(service.getRequirementApplications('org-1', 'req-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('returns applications for a requirement the caller owns', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.findByRequirementId.mockResolvedValue([{ id: 'app-1' }]);
      const result = await service.getRequirementApplications('org-1', 'req-1');
      expect(result).toEqual([{ id: 'app-1' }]);
    });
  });

  describe('getApplicantProfile', () => {
    it('throws GEN_002 when the requirement belongs to someone else', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'someone-else' });
      await expect(service.getApplicantProfile('org-1', 'req-1', 'app-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(caregiverService.getApplicantProfile).not.toHaveBeenCalled();
    });

    it('throws GEN_002 when the application does not belong to this requirement', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.findById.mockResolvedValue({
        id: 'app-1',
        requirement_id: 'some-other-req',
        profile_id: 'p-1',
      });
      await expect(service.getApplicantProfile('org-1', 'req-1', 'app-1')).rejects.toMatchObject({
        code: 'GEN_002',
      });
      expect(caregiverService.getApplicantProfile).not.toHaveBeenCalled();
    });

    it("delegates to CaregiverService.getApplicantProfile with the application's profile_id", async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.findById.mockResolvedValue({ id: 'app-1', requirement_id: 'req-1', profile_id: 'profile-1' });
      caregiverService.getApplicantProfile.mockResolvedValue({ full_name: 'Nurse Nita' });
      const result = await service.getApplicantProfile('org-1', 'req-1', 'app-1');
      expect(caregiverService.getApplicantProfile).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({ full_name: 'Nurse Nita' });
    });
  });

  describe('decideMyApplication', () => {
    it('throws GEN_002 when the requirement belongs to someone else', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'someone-else' });
      await expect(
        service.decideMyApplication('org-1', 'req-1', 'app-1', { status: 'accepted' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('delegates to decideApplication when the caller owns the requirement', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.findById.mockResolvedValue({
        id: 'app-1',
        requirement_id: 'req-1',
        profile_id: 'profile-1',
        status: 'applied',
      });
      adminCaregiversRepo.getDetailById.mockResolvedValue({ user_id: 'caregiver-user-1' });

      const result = await service.decideMyApplication(
        'org-1',
        'req-1',
        'app-1',
        { status: 'accepted' } as any,
        '127.0.0.1',
      );

      expect(applicationsRepo.decide).toHaveBeenCalledWith('app-1', 'accepted', 'org-1', {}, undefined);
      expect(requirementsRepo.close).toHaveBeenCalledWith('req-1', {});
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });
  });

  describe('decideApplication', () => {
    const application = {
      id: 'app-1',
      requirement_id: 'req-1',
      profile_id: 'profile-1',
      status: 'applied',
    };
    const caregiverDetail = { user_id: 'caregiver-user-1' };

    it('throws JOB_006 when the application does not exist', async () => {
      applicationsRepo.findById.mockResolvedValue(null);
      await expect(
        service.decideApplication('admin-1', 'req-1', 'missing', { status: 'accepted' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('throws JOB_006 when the application belongs to a different requirement', async () => {
      applicationsRepo.findById.mockResolvedValue({ ...application, requirement_id: 'other-req' });
      await expect(
        service.decideApplication('admin-1', 'req-1', 'app-1', { status: 'accepted' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('throws JOB_007 for an invalid transition (double-accept)', async () => {
      applicationsRepo.findById.mockResolvedValue({ ...application, status: 'accepted' });
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);
      await expect(
        service.decideApplication('admin-1', 'req-1', 'app-1', { status: 'accepted' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_007' });
    });

    it('accepts an applied application: closes the requirement and assigns the caregiver', async () => {
      applicationsRepo.findById.mockResolvedValue(application);
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      const result = await service.decideApplication(
        'admin-1',
        'req-1',
        'app-1',
        { status: 'accepted' } as any,
        null,
      );

      expect(applicationsRepo.decide).toHaveBeenCalledWith('app-1', 'accepted', 'admin-1', {}, undefined);
      expect(requirementsRepo.close).toHaveBeenCalledWith('req-1', {});
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith('profile-1', 'assigned', null, 'admin-1', {});
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });

    it('rejecting a previously-accepted application reopens the requirement and un-assigns the caregiver', async () => {
      applicationsRepo.findById.mockResolvedValue({ ...application, status: 'accepted' });
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      await service.decideApplication('admin-1', 'req-1', 'app-1', { status: 'rejected' } as any, null);

      expect(requirementsRepo.reopen).toHaveBeenCalledWith('req-1', {});
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith('profile-1', 'available', null, 'admin-1', {});
    });

    it('rejects a still-applied application with no requirement/caregiver side effects, reason passed through', async () => {
      applicationsRepo.findById.mockResolvedValue(application);
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      await service.decideApplication(
        'admin-1',
        'req-1',
        'app-1',
        { status: 'rejected', reason: 'Not a fit' } as any,
        null,
      );

      expect(applicationsRepo.decide).toHaveBeenCalledWith('app-1', 'rejected', 'admin-1', {}, 'Not a fit');
      expect(requirementsRepo.close).not.toHaveBeenCalled();
      expect(requirementsRepo.reopen).not.toHaveBeenCalled();
      expect(adminCaregiversRepo.updateStatus).not.toHaveBeenCalled();
    });
  });

  describe('applyToRequirement', () => {
    it('throws PROFILE_019 when no caregiver profile exists', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(
        service.applyToRequirement('user-1', 'req-1', { status: 'applied' } as any, null),
      ).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it('throws JOB_001 when not available/assigned', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: 'pending_call' });
      await expect(
        service.applyToRequirement('user-1', 'req-1', { status: 'applied' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_001' });
    });

    it('throws GEN_002 when the requirement does not exist', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: 'available' });
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(
        service.applyToRequirement('user-1', 'req-1', { status: 'applied' } as any, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws JOB_002 when the requirement is not active', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: 'available' });
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'closed' });
      await expect(
        service.applyToRequirement('user-1', 'req-1', { status: 'applied' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_002' });
    });

    it('records the application on success', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', verification_status: 'available' });
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'active' });
      applicationsRepo.upsert.mockResolvedValue({ id: 'app-1', status: 'applied' });

      const result = await service.applyToRequirement('user-1', 'req-1', { status: 'applied' } as any, null);

      expect(applicationsRepo.upsert).toHaveBeenCalledWith('req-1', 'profile-1', 'applied');
      expect(result).toEqual({ message: 'Application recorded', status: 'applied' });
    });
  });

  describe('completeRequirement', () => {
    it('throws JOB_008 when there is no active accepted application', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue(null);
      await expect(service.completeRequirement('user-1', 'req-1', null)).rejects.toMatchObject({ code: 'JOB_008' });
    });

    it('marks the application completed and drops the caregiver back to available when no other accepted requirements remain', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue({ id: 'app-1', status: 'accepted' });
      applicationsRepo.countAcceptedByProfileId.mockResolvedValue(0);

      const result = await service.completeRequirement('user-1', 'req-1', null);

      expect(applicationsRepo.markCompleted).toHaveBeenCalledWith('app-1', {});
      expect(caregiverProfilesRepo.markAvailable).toHaveBeenCalledWith('profile-1', {});
      expect(result.verification_status).toBe('available');
    });

    it('leaves the caregiver assigned when another accepted requirement remains', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue({ id: 'app-1', status: 'accepted' });
      applicationsRepo.countAcceptedByProfileId.mockResolvedValue(1);

      const result = await service.completeRequirement('user-1', 'req-1', null);

      expect(caregiverProfilesRepo.markAvailable).not.toHaveBeenCalled();
      expect(result.verification_status).toBe('assigned');
    });
  });

  describe('updateRequirement (admin approve-via-edit)', () => {
    const editDto = {
      type_of_nurse: 'registered_nurse',
      frequency_of_care: 'monthly',
      salary_amount: 40000,
      schedule_type: 'specific_days',
      specific_days: [3, 12, 20],
      accommodation_provided: true,
      food_provided: true,
    } as any;

    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.updateRequirement('admin-1', 'req-1', editDto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('activates a pending_review requirement and broadcasts a push', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'pending_review' });
      requirementsRepo.update.mockResolvedValue({ id: 'req-1', status: 'active' });

      await service.updateRequirement('admin-1', 'req-1', editDto, null);

      expect(requirementsRepo.update).toHaveBeenCalledWith(
        'req-1',
        expect.objectContaining({ activate: true, schedule_type: 'specific_days', specific_days: [3, 12, 20] }),
      );
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalled();
    });

    it('does not re-broadcast a push for a plain edit of an already-active requirement', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'active' });
      requirementsRepo.update.mockResolvedValue({ id: 'req-1', status: 'active' });

      await service.updateRequirement('admin-1', 'req-1', editDto, null);

      expect(requirementsRepo.update).toHaveBeenCalledWith('req-1', expect.objectContaining({ activate: false }));
      expect(fcmService.sendToAllCaregivers).not.toHaveBeenCalled();
    });

    it('nulls specific_days when schedule_type is date_range, and persists start_date/end_date', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'active' });
      requirementsRepo.update.mockResolvedValue({ id: 'req-1', status: 'active' });

      await service.updateRequirement(
        'admin-1',
        'req-1',
        { ...editDto, schedule_type: 'date_range', start_date: '2026-09-01', end_date: '2026-09-10' },
        null,
      );

      expect(requirementsRepo.update).toHaveBeenCalledWith(
        'req-1',
        expect.objectContaining({
          schedule_type: 'date_range',
          start_date: '2026-09-01',
          end_date: '2026-09-10',
          specific_days: null,
        }),
      );
    });

    it('nulls start_date/end_date when schedule_type is specific_days, and persists specific_days', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'active' });
      requirementsRepo.update.mockResolvedValue({ id: 'req-1', status: 'active' });

      await service.updateRequirement(
        'admin-1',
        'req-1',
        { ...editDto, schedule_type: 'specific_days', specific_days: [5, 15, 25] },
        null,
      );

      expect(requirementsRepo.update).toHaveBeenCalledWith(
        'req-1',
        expect.objectContaining({
          schedule_type: 'specific_days',
          start_date: null,
          end_date: null,
          specific_days: [5, 15, 25],
        }),
      );
    });

    it('throws ORG_001 when end_date is before start_date for a date_range schedule', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'active' });

      await expect(
        service.updateRequirement(
          'admin-1',
          'req-1',
          { ...editDto, schedule_type: 'date_range', start_date: '2026-09-10', end_date: '2026-09-01' },
          null,
        ),
      ).rejects.toMatchObject({ code: 'ORG_001' });
      expect(requirementsRepo.update).not.toHaveBeenCalled();
    });
  });

  describe('rejectRequirement', () => {
    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.rejectRequirement('admin-1', 'req-1', 'reason', null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_011 when the requirement is not pending_review', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'active' });
      await expect(service.rejectRequirement('admin-1', 'req-1', 'reason', null)).rejects.toMatchObject({
        code: 'JOB_011',
      });
    });

    it('rejects a pending_review requirement', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', status: 'pending_review' });
      const result = await service.rejectRequirement('admin-1', 'req-1', 'Not needed', '127.0.0.1');
      expect(requirementsRepo.reject).toHaveBeenCalledWith('req-1', 'Not needed', undefined);
      expect(result).toEqual({ message: 'Requirement rejected', status: 'closed' });
    });
  });

  describe('listRequirementsForAdmin / getRequirementDetailForAdmin', () => {
    it('paginates and shapes meta correctly', async () => {
      requirementsRepo.listForAdmin.mockResolvedValue({ items: [{ id: 'req-1' }], total: 5 });
      const result = await service.listRequirementsForAdmin({ page: 1, limit: 20 } as any);
      expect(result.meta).toEqual({ page: 1, limit: 20, total: 5, totalPages: 1 });
    });

    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.getRequirementDetailForAdmin('req-1')).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('includes applications in the detail response', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1' });
      applicationsRepo.findByRequirementId.mockResolvedValue([{ id: 'app-1' }]);
      const result = await service.getRequirementDetailForAdmin('req-1');
      expect(result.applications).toEqual([{ id: 'app-1' }]);
    });
  });
});
