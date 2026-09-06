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
    duration_type: 'short_term',
  } as any;

  beforeEach(() => {
    db = { withTransaction: jest.fn(async (fn: any) => fn({})) };
    requirementsRepo = {
      create: jest.fn(),
      findById: jest.fn(),
      listByPostedBy: jest.fn(),
      listActiveForCaregiver: jest.fn(),
      listForAdmin: jest.fn(),
      activate: jest.fn(),
      updateOwnFields: jest.fn(),
      reject: jest.fn(),
      close: jest.fn(),
      reopen: jest.fn(),
      cancel: jest.fn(),
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
      hasAnyApplicationForRequirement: jest.fn(),
    };
    caregiverProfilesRepo = { findByUserId: jest.fn(), markAvailable: jest.fn() };
    adminCaregiversRepo = { getDetailById: jest.fn(), updateStatus: jest.fn() };
    organisationProfilesRepo = { findByUserId: jest.fn(), findByUserIdWithPhone: jest.fn() };
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

    it('defaults number_of_vacancies to 1 when omitted', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      requirementsRepo.create.mockResolvedValue({ id: 'req-1' });

      await service.createRequirement('org-1', createDto, null);

      expect(requirementsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({ number_of_vacancies: 1, preferred_gender: null, type_of_nurse_other: null }),
      );
    });

    it('persists number_of_vacancies/preferred_gender/type_of_nurse_other when provided', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      requirementsRepo.create.mockResolvedValue({ id: 'req-1' });

      await service.createRequirement(
        'org-1',
        { ...createDto, type_of_nurse: 'others', type_of_nurse_other: 'Wound care specialist', number_of_vacancies: 5, preferred_gender: 'female' },
        null,
      );

      expect(requirementsRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          type_of_nurse_other: 'Wound care specialist',
          number_of_vacancies: 5,
          preferred_gender: 'female',
        }),
      );
    });

    it('nulls type_of_nurse_other when type_of_nurse is not others, even if sent', async () => {
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      requirementsRepo.create.mockResolvedValue({ id: 'req-1' });

      await service.createRequirement(
        'org-1',
        { ...createDto, type_of_nurse: 'registered_nurse', type_of_nurse_other: 'should be ignored' },
        null,
      );

      expect(requirementsRepo.create).toHaveBeenCalledWith(expect.objectContaining({ type_of_nurse_other: null }));
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
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1', cancelled_at: null });
      applicationsRepo.findByRequirementId.mockResolvedValue([{ id: 'app-1' }]);
      const result = await service.getRequirementApplications('org-1', 'req-1');
      expect(result).toEqual([{ id: 'app-1' }]);
    });

    it('still returns applications once the requirement is cancelled — cancelling never hides applicants', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        cancelled_at: new Date(),
      });
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
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1', cancelled_at: null });
      applicationsRepo.findById.mockResolvedValue({ id: 'app-1', requirement_id: 'req-1', profile_id: 'profile-1' });
      caregiverService.getApplicantProfile.mockResolvedValue({ full_name: 'Nurse Nita' });
      const result = await service.getApplicantProfile('org-1', 'req-1', 'app-1');
      expect(caregiverService.getApplicantProfile).toHaveBeenCalledWith('profile-1');
      expect(result).toEqual({ full_name: 'Nurse Nita' });
    });

    it('still returns the profile once the requirement is cancelled — cancelling never hides applicants', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1', cancelled_at: new Date() });
      applicationsRepo.findById.mockResolvedValue({ id: 'app-1', requirement_id: 'req-1', profile_id: 'profile-1' });
      caregiverService.getApplicantProfile.mockResolvedValue({ full_name: 'Nurse Nita' });
      const result = await service.getApplicantProfile('org-1', 'req-1', 'app-1');
      expect(result).toEqual({ full_name: 'Nurse Nita' });
    });
  });

  describe('listActiveForCaregiver', () => {
    it('throws PROFILE_019 when no caregiver profile exists', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue(null);
      await expect(service.listActiveForCaregiver('user-1')).rejects.toMatchObject({ code: 'PROFILE_019' });
    });

    it("passes the caregiver's own gender through, so preferred_gender filtering matches jobs' own behavior", async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1', gender: 'female' });
      requirementsRepo.listActiveForCaregiver.mockResolvedValue([{ id: 'req-1' }]);

      const result = await service.listActiveForCaregiver('user-1');

      expect(requirementsRepo.listActiveForCaregiver).toHaveBeenCalledWith('profile-1', 'female');
      expect(result).toEqual([{ id: 'req-1' }]);
    });
  });

  describe('editRequirement', () => {
    const editDto = {
      type_of_nurse: 'registered_nurse',
      accommodation_provided: true,
      food_provided: false,
      number_of_vacancies: 2,
      duration_type: 'long_term',
    } as any;

    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.editRequirement('org-1', 'req-1', editDto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws GEN_002 when the requirement belongs to someone else', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'someone-else' });
      await expect(service.editRequirement('org-1', 'req-1', editDto, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_014 when any application exists at all — even a rejected or completed one, not just '
      + 'an active applied/accepted one (a deliberately stricter rule than the jobs pipeline)', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.hasAnyApplicationForRequirement.mockResolvedValue(true);
      await expect(service.editRequirement('org-1', 'req-1', editDto, null)).rejects.toMatchObject({
        code: 'JOB_014',
      });
      expect(requirementsRepo.updateOwnFields).not.toHaveBeenCalled();
    });

    it('calls hasAnyApplicationForRequirement (not the active-only check) when deciding whether editing is locked',
      async () => {
        requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
        applicationsRepo.hasAnyApplicationForRequirement.mockResolvedValue(false);
        requirementsRepo.updateOwnFields.mockResolvedValue({ id: 'req-1' });

        await service.editRequirement('org-1', 'req-1', editDto, null);

        expect(applicationsRepo.hasAnyApplicationForRequirement).toHaveBeenCalledWith('req-1');
      });

    it('updates only the org-owned fields, regardless of the requirement status', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        status: 'active',
        type_of_nurse: 'nursing_completed',
      });
      applicationsRepo.hasAnyApplicationForRequirement.mockResolvedValue(false);
      requirementsRepo.updateOwnFields.mockResolvedValue({
        id: 'req-1',
        status: 'active',
        type_of_nurse: 'registered_nurse',
      });

      const result = await service.editRequirement('org-1', 'req-1', editDto, '127.0.0.1');

      expect(requirementsRepo.updateOwnFields).toHaveBeenCalledWith('req-1', {
        type_of_nurse: 'registered_nurse',
        type_of_nurse_other: null,
        accommodation_provided: true,
        food_provided: false,
        special_skills: null,
        number_of_vacancies: 2,
        preferred_gender: null,
        duration_type: 'long_term',
      });
      expect(result.id).toBe('req-1');
    });

    it('persists type_of_nurse_other only when type_of_nurse is others', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.hasAnyApplicationForRequirement.mockResolvedValue(false);
      requirementsRepo.updateOwnFields.mockResolvedValue({ id: 'req-1' });

      await service.editRequirement(
        'org-1',
        'req-1',
        { ...editDto, type_of_nurse: 'others', type_of_nurse_other: 'Physiotherapist' },
        null,
      );

      expect(requirementsRepo.updateOwnFields).toHaveBeenCalledWith(
        'req-1',
        expect.objectContaining({ type_of_nurse: 'others', type_of_nurse_other: 'Physiotherapist' }),
      );
    });
  });

  describe('cancelRequirement', () => {
    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.cancelRequirement('org-1', 'req-1', null)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws GEN_002 when the requirement belongs to someone else', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'someone-else' });
      await expect(service.cancelRequirement('org-1', 'req-1', null)).rejects.toMatchObject({ code: 'GEN_002' });
    });

    it('throws JOB_015 when already cancelled', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        cancelled_at: new Date(),
        rejection_reason: null,
      });
      await expect(service.cancelRequirement('org-1', 'req-1', null)).rejects.toMatchObject({ code: 'JOB_015' });
    });

    it('throws JOB_015 when already admin-rejected', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        cancelled_at: null,
        rejection_reason: 'Not needed',
      });
      await expect(service.cancelRequirement('org-1', 'req-1', null)).rejects.toMatchObject({ code: 'JOB_015' });
    });

    it('cancels the requirement without touching any application — cancelling only stops new applications', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        status: 'active',
        cancelled_at: null,
        rejection_reason: null,
      });

      const result = await service.cancelRequirement('org-1', 'req-1', '127.0.0.1');

      expect(applicationsRepo.decide).not.toHaveBeenCalled();
      expect(caregiverProfilesRepo.markAvailable).not.toHaveBeenCalled();
      expect(requirementsRepo.cancel).toHaveBeenCalledWith('req-1');
      expect(result).toEqual({ message: 'Requirement cancelled', status: 'closed' });
    });
  });

  describe('reactivateRequirement', () => {
    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.reactivateRequirement('org-1', 'req-1', null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws GEN_002 when the requirement belongs to someone else', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'someone-else', cancelled_at: new Date() });
      await expect(service.reactivateRequirement('org-1', 'req-1', null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('throws JOB_017 when the requirement was never cancelled', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1', cancelled_at: null });
      await expect(service.reactivateRequirement('org-1', 'req-1', null)).rejects.toMatchObject({
        code: 'JOB_017',
      });
      expect(requirementsRepo.activate).not.toHaveBeenCalled();
    });

    it('throws JOB_010 when the account is job-posting-blocked — reactivating makes it appliable again, '
      + 'same as posting new', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        status: 'closed',
        cancelled_at: new Date(),
      });
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: true });

      await expect(service.reactivateRequirement('org-1', 'req-1', null)).rejects.toMatchObject({
        code: 'JOB_010',
      });
      expect(requirementsRepo.activate).not.toHaveBeenCalled();
    });

    it('reactivates a cancelled requirement, stamps posted_at, and broadcasts a push', async () => {
      requirementsRepo.findById.mockResolvedValue({
        id: 'req-1',
        posted_by: 'org-1',
        status: 'closed',
        cancelled_at: new Date(),
      });
      organisationProfilesRepo.findByUserId.mockResolvedValue({ is_job_posting_blocked: false });
      requirementsRepo.activate.mockResolvedValue({ id: 'req-1', status: 'active' });

      const result = await service.reactivateRequirement('org-1', 'req-1', '127.0.0.1');

      expect(requirementsRepo.activate).toHaveBeenCalledWith('req-1');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalled();
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'org-1', action: 'org_requirement_updated', entityId: 'req-1' }),
      );
      expect(result).toEqual({ id: 'req-1', status: 'active' });
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
      expect(requirementsRepo.close).not.toHaveBeenCalled();
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });

    it('throws JOB_012 when rejecting without a reason', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      await expect(
        service.decideMyApplication('org-1', 'req-1', 'app-1', { status: 'rejected' } as any, null),
      ).rejects.toMatchObject({ code: 'JOB_012' });
      expect(applicationsRepo.findById).not.toHaveBeenCalled();
    });

    it('throws JOB_012 when rejecting with a blank/whitespace-only reason', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      await expect(
        service.decideMyApplication(
          'org-1',
          'req-1',
          'app-1',
          { status: 'rejected', reason: '   ' } as any,
          null,
        ),
      ).rejects.toMatchObject({ code: 'JOB_012' });
    });

    it('accepting never requires a reason', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.findById.mockResolvedValue({
        id: 'app-1',
        requirement_id: 'req-1',
        profile_id: 'profile-1',
        status: 'applied',
      });
      adminCaregiversRepo.getDetailById.mockResolvedValue({ user_id: 'caregiver-user-1' });

      await service.decideMyApplication('org-1', 'req-1', 'app-1', { status: 'accepted' } as any, null);
      expect(applicationsRepo.decide).toHaveBeenCalled();
    });

    it('rejecting with a reason delegates through, reason intact', async () => {
      requirementsRepo.findById.mockResolvedValue({ id: 'req-1', posted_by: 'org-1' });
      applicationsRepo.findById.mockResolvedValue({
        id: 'app-1',
        requirement_id: 'req-1',
        profile_id: 'profile-1',
        status: 'applied',
      });
      adminCaregiversRepo.getDetailById.mockResolvedValue({ user_id: 'caregiver-user-1' });

      await service.decideMyApplication(
        'org-1',
        'req-1',
        'app-1',
        { status: 'rejected', reason: 'Schedule does not match' } as any,
        null,
      );
      expect(applicationsRepo.decide).toHaveBeenCalledWith(
        'app-1',
        'rejected',
        'org-1',
        {},
        'Schedule does not match',
      );
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

    it('accepts an applied application: assigns the caregiver, and never touches the requirement\'s own status', async () => {
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
      expect(requirementsRepo.close).not.toHaveBeenCalled();
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith('profile-1', 'assigned', null, 'admin-1', {});
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });

    it('rejecting a previously-accepted application un-assigns the caregiver without touching the requirement\'s own status', async () => {
      applicationsRepo.findById.mockResolvedValue({ ...application, status: 'accepted' });
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      await service.decideApplication('admin-1', 'req-1', 'app-1', { status: 'rejected' } as any, null);

      expect(requirementsRepo.reopen).not.toHaveBeenCalled();
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

    it('accepts a previously-rejected application ("Accept Anyway" — either side can reconsider), assigning '
      + 'the caregiver same as a fresh accept, without touching the requirement\'s own status', async () => {
      applicationsRepo.findById.mockResolvedValue({ ...application, status: 'rejected' });
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      const result = await service.decideApplication(
        'admin-1',
        'req-1',
        'app-1',
        { status: 'accepted' } as any,
        null,
      );

      expect(applicationsRepo.decide).toHaveBeenCalledWith('app-1', 'accepted', 'admin-1', {}, undefined);
      expect(requirementsRepo.close).not.toHaveBeenCalled();
      expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith('profile-1', 'assigned', null, 'admin-1', {});
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });

    it('accepts a previously-completed application ("Accept Anyway" after the caregiver closed the requirement '
      + 'themselves), assigning the caregiver same as a fresh accept, without touching the requirement\'s own status', async () => {
      applicationsRepo.findById.mockResolvedValue({ ...application, status: 'completed' });
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      const result = await service.decideApplication(
        'admin-1',
        'req-1',
        'app-1',
        { status: 'accepted' } as any,
        null,
      );

      expect(applicationsRepo.decide).toHaveBeenCalledWith('app-1', 'accepted', 'admin-1', {}, undefined);
      expect(requirementsRepo.close).not.toHaveBeenCalled();
      expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
    });

    it.each(['applied', 'rejected', 'completed'])(
      'accepts a %s application regardless of how many others are already accepted on the same requirement '
      + '(number_of_vacancies is informational only, never an accept cap — an earlier iteration enforced it '
      + 'via JOB_019, reversed on explicit follow-up request)',
      async (status) => {
        applicationsRepo.findById.mockResolvedValue({ ...application, status });
        adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

        const result = await service.decideApplication(
          'admin-1',
          'req-1',
          'app-1',
          { status: 'accepted' } as any,
          null,
        );

        expect(applicationsRepo.decide).toHaveBeenCalledWith('app-1', 'accepted', 'admin-1', {}, undefined);
        expect(adminCaregiversRepo.updateStatus).toHaveBeenCalledWith('profile-1', 'assigned', null, 'admin-1', {});
        expect(result).toEqual({ message: 'Application updated', status: 'accepted' });
      },
    );

    it('never consults the requirement at all when deciding — accepting is not gated on '
      + 'number_of_vacancies for either accept or reject', async () => {
      applicationsRepo.findById.mockResolvedValue(application);
      adminCaregiversRepo.getDetailById.mockResolvedValue(caregiverDetail);

      await service.decideApplication('admin-1', 'req-1', 'app-1', { status: 'accepted' } as any, null);

      expect(requirementsRepo.findById).not.toHaveBeenCalled();
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
      await expect(service.completeRequirement('user-1', 'req-1', {}, null)).rejects.toMatchObject({
        code: 'JOB_008',
      });
    });

    it('marks the application completed and drops the caregiver back to available when no other accepted requirements remain', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue({ id: 'app-1', status: 'accepted' });
      applicationsRepo.countAcceptedByProfileId.mockResolvedValue(0);

      const result = await service.completeRequirement('user-1', 'req-1', {}, null);

      expect(applicationsRepo.markCompleted).toHaveBeenCalledWith('app-1', 'no_reason', {});
      expect(caregiverProfilesRepo.markAvailable).toHaveBeenCalledWith('profile-1', {});
      expect(result.verification_status).toBe('available');
    });

    it('defaults close_reason to no_reason when omitted, and persists a specific one when provided', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue({ id: 'app-1', status: 'accepted' });
      applicationsRepo.countAcceptedByProfileId.mockResolvedValue(0);

      await service.completeRequirement('user-1', 'req-1', { close_reason: 'need_to_go_hometown' }, null);

      expect(applicationsRepo.markCompleted).toHaveBeenCalledWith('app-1', 'need_to_go_hometown', {});
    });

    it('never touches the requirement\'s own status — it was never closed by acceptance in the first place', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue({ id: 'app-1', status: 'accepted' });
      applicationsRepo.countAcceptedByProfileId.mockResolvedValue(0);

      await service.completeRequirement('user-1', 'req-1', {}, null);

      expect(requirementsRepo.reopen).not.toHaveBeenCalled();
    });

    it('leaves the caregiver assigned when another accepted requirement remains', async () => {
      caregiverProfilesRepo.findByUserId.mockResolvedValue({ id: 'profile-1' });
      applicationsRepo.findByRequirementAndProfile.mockResolvedValue({ id: 'app-1', status: 'accepted' });
      applicationsRepo.countAcceptedByProfileId.mockResolvedValue(1);

      const result = await service.completeRequirement('user-1', 'req-1', {}, null);

      expect(caregiverProfilesRepo.markAvailable).not.toHaveBeenCalled();
      expect(result.verification_status).toBe('assigned');
    });
  });

  describe('adminEditRequirement', () => {
    const existing = {
      id: 'req-1',
      status: 'pending_review',
      type_of_nurse: 'registered_nurse',
      type_of_nurse_other: null,
      accommodation_provided: true,
      food_provided: false,
      special_skills: 'Wound care',
      number_of_vacancies: 2,
      preferred_gender: 'female',
      duration_type: 'long_term',
    };

    beforeEach(() => {
      requirementsRepo.updateOwnFields.mockImplementation(async (_id: string, fields: any) => ({
        ...existing,
        ...fields,
      }));
    });

    it('throws GEN_002 when the requirement does not exist', async () => {
      requirementsRepo.findById.mockResolvedValue(null);
      await expect(service.adminEditRequirement('admin-1', 'req-1', {}, null)).rejects.toMatchObject({
        code: 'GEN_002',
      });
    });

    it('a bare/empty body keeps every existing field unchanged (pure approve, same as the old approveRequirement)',
      async () => {
        requirementsRepo.findById.mockResolvedValue(existing);
        requirementsRepo.activate.mockResolvedValue({ ...existing, status: 'active' });

        await service.adminEditRequirement('admin-1', 'req-1', {}, '127.0.0.1');

        expect(requirementsRepo.updateOwnFields).toHaveBeenCalledWith('req-1', {
          type_of_nurse: 'registered_nurse',
          type_of_nurse_other: null,
          accommodation_provided: true,
          food_provided: false,
          special_skills: 'Wound care',
          number_of_vacancies: 2,
          preferred_gender: 'female',
          duration_type: 'long_term',
        });
      });

    it('overrides only the fields provided, keeping every other field as-is', async () => {
      requirementsRepo.findById.mockResolvedValue(existing);
      requirementsRepo.activate.mockResolvedValue({ ...existing, status: 'active' });

      await service.adminEditRequirement(
        'admin-1',
        'req-1',
        { number_of_vacancies: 5, food_provided: true },
        null,
      );

      expect(requirementsRepo.updateOwnFields).toHaveBeenCalledWith(
        'req-1',
        expect.objectContaining({ number_of_vacancies: 5, food_provided: true, accommodation_provided: true }),
      );
    });

    it('activates a pending_review requirement, stamps posted_at, and broadcasts a push', async () => {
      requirementsRepo.findById.mockResolvedValue(existing);
      requirementsRepo.activate.mockResolvedValue({ ...existing, status: 'active' });

      const result = await service.adminEditRequirement('admin-1', 'req-1', {}, '127.0.0.1');

      expect(requirementsRepo.activate).toHaveBeenCalledWith('req-1');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalled();
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'admin-1', action: 'org_requirement_updated', entityId: 'req-1' }),
      );
      expect(result.status).toBe('active');
    });

    it('reactivates (reposts) an already-closed requirement, same as reactivating from pending_review', async () => {
      requirementsRepo.findById.mockResolvedValue({ ...existing, status: 'closed' });
      requirementsRepo.activate.mockResolvedValue({ ...existing, status: 'active' });

      await service.adminEditRequirement('admin-1', 'req-1', {}, null);

      expect(requirementsRepo.activate).toHaveBeenCalledWith('req-1');
      expect(fcmService.sendToAllCaregivers).toHaveBeenCalled();
    });

    it('saves field changes on an already-active requirement without reactivating or re-broadcasting the push',
      async () => {
        requirementsRepo.findById.mockResolvedValue({ ...existing, status: 'active' });

        const result = await service.adminEditRequirement(
          'admin-1',
          'req-1',
          { number_of_vacancies: 9 },
          null,
        );

        expect(requirementsRepo.activate).not.toHaveBeenCalled();
        expect(fcmService.sendToAllCaregivers).not.toHaveBeenCalled();
        expect(requirementsRepo.updateOwnFields).toHaveBeenCalledWith(
          'req-1',
          expect.objectContaining({ number_of_vacancies: 9 }),
        );
        expect(auditService.log).toHaveBeenCalled();
        expect(result.number_of_vacancies).toBe(9);
      });

    it('throws GEN_001 when switching type_of_nurse to others without a free-text description', async () => {
      requirementsRepo.findById.mockResolvedValue(existing);

      await expect(
        service.adminEditRequirement('admin-1', 'req-1', { type_of_nurse: 'others' }, null),
      ).rejects.toMatchObject({ code: 'GEN_001' });
    });

    it('keeps the existing type_of_nurse_other when type_of_nurse stays others and it is not resent', async () => {
      requirementsRepo.findById.mockResolvedValue({
        ...existing,
        type_of_nurse: 'others',
        type_of_nurse_other: 'Physiotherapist',
      });
      requirementsRepo.activate.mockResolvedValue({ ...existing, status: 'active' });

      await service.adminEditRequirement('admin-1', 'req-1', { food_provided: true }, null);

      expect(requirementsRepo.updateOwnFields).toHaveBeenCalledWith(
        'req-1',
        expect.objectContaining({ type_of_nurse: 'others', type_of_nurse_other: 'Physiotherapist' }),
      );
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

    it('passes posted_by/organisation_type/city/search filters through to the repository, alongside status', async () => {
      requirementsRepo.listForAdmin.mockResolvedValue({ items: [], total: 0 });
      await service.listRequirementsForAdmin({
        page: 1,
        limit: 20,
        status: 'active',
        posted_by: 'org-user-1',
        organisation_type: 'hospital',
        city: 'bangalore',
        search: 'City Rehab',
      } as any);
      expect(requirementsRepo.listForAdmin).toHaveBeenCalledWith(
        {
          status: 'active',
          posted_by: 'org-user-1',
          organisation_type: 'hospital',
          city: 'bangalore',
          search: 'City Rehab',
        },
        { page: 1, limit: 20 },
      );
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
