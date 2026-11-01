import { NotificationsService } from './notifications.service';

describe('NotificationsService', () => {
  let usersRepo: any;
  let fcmService: any;
  let jobApplicationsRepo: any;
  let orgApplicationsRepo: any;
  let service: NotificationsService;

  const minutesAgo = (m: number) => new Date(Date.now() - m * 60 * 1000);

  beforeEach(() => {
    usersRepo = { findById: jest.fn(), hasFcmToken: jest.fn(), updateFcmToken: jest.fn() };
    fcmService = { sendToUser: jest.fn().mockResolvedValue(undefined) };
    jobApplicationsRepo = { countAppliedSince: jest.fn(), countApplied: jest.fn(), listApplicantUsers: jest.fn() };
    orgApplicationsRepo = { countAppliedSince: jest.fn(), countApplied: jest.fn(), listApplicantUsers: jest.fn() };
    service = new NotificationsService(usersRepo, fcmService, jobApplicationsRepo, orgApplicationsRepo);
  });

  describe('registerDevice', () => {
    it('saves the device and welcomes a brand-new caregiver on their first device', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', role: 'caregiver', created_at: minutesAgo(1) });
      usersRepo.hasFcmToken.mockResolvedValue(false);

      await service.registerDevice('u1', 'tok');

      expect(usersRepo.updateFcmToken).toHaveBeenCalledWith('u1', 'tok');
      expect(fcmService.sendToUser).toHaveBeenCalledWith(
        'u1',
        'Registration received',
        expect.any(String),
        { route: '/caregiver/profile' },
      );
    });

    it.each([
      ['individual', '/home', 'Requirement submitted'],
      ['organisation', '/org-home', 'Welcome to JustHeal'],
    ])('welcomes a new %s with a tap target on their own home screen', async (role, route, title) => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', role, created_at: minutesAgo(2) });
      usersRepo.hasFcmToken.mockResolvedValue(false);
      await service.registerDevice('u1', 'tok');
      expect(fcmService.sendToUser).toHaveBeenCalledWith('u1', title, expect.any(String), { route });
    });

    it('does not welcome an account that already had a device (a later login, or after logout)', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', role: 'caregiver', created_at: minutesAgo(1) });
      usersRepo.hasFcmToken.mockResolvedValue(true);
      await service.registerDevice('u1', 'tok');
      expect(usersRepo.updateFcmToken).toHaveBeenCalled();
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });

    it('does not welcome an old account registering its first device (e.g. after reinstalling)', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', role: 'caregiver', created_at: minutesAgo(60 * 24) });
      usersRepo.hasFcmToken.mockResolvedValue(false);
      await service.registerDevice('u1', 'tok');
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });

    it('still saves the device if sending the welcome fails', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', role: 'caregiver', created_at: minutesAgo(1) });
      usersRepo.hasFcmToken.mockResolvedValue(false);
      fcmService.sendToUser.mockRejectedValue(new Error('fcm down'));
      await expect(service.registerDevice('u1', 'tok')).resolves.toBeUndefined();
      expect(usersRepo.updateFcmToken).toHaveBeenCalledWith('u1', 'tok');
    });

    it('lets a real save failure through — the caller must know the device was not registered', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'u1', role: 'caregiver', created_at: minutesAgo(1) });
      usersRepo.hasFcmToken.mockResolvedValue(false);
      usersRepo.updateFcmToken.mockRejectedValue(new Error('db down'));
      await expect(service.registerDevice('u1', 'tok')).rejects.toThrow('db down');
    });
  });

  describe('requirement approved / rejected', () => {
    it('tells a patient, pointing at their own home screen', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'p1', role: 'individual' });
      await service.requirementApproved('p1', 'PAT-JOB-512');
      expect(fcmService.sendToUser).toHaveBeenCalledWith('p1', 'Your requirement is live', expect.stringContaining('PAT-JOB-512'), {
        route: '/home',
      });
    });

    it('includes the rejection reason', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'o1', role: 'organisation' });
      await service.requirementRejected('o1', 'ORG-JOB-7', 'Missing details');
      expect(fcmService.sendToUser).toHaveBeenCalledWith('o1', 'Requirement not approved', expect.stringContaining('Missing details'), {
        route: '/org-home',
      });
    });

    it('sends nothing to an admin poster — admins have no app', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'a1', role: 'super_admin' });
      await service.requirementApproved('a1', 'ADMIN-JOB-1');
      await service.requirementRejected('a1', 'ADMIN-JOB-1', 'x');
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });
  });

  describe('jobApplied', () => {
    const job = { id: 'job-1', posted_by: 'p1' };

    it('announces the first applicant of a burst, with the running total', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'p1', role: 'individual' });
      jobApplicationsRepo.countAppliedSince.mockResolvedValue(1);
      jobApplicationsRepo.countApplied.mockResolvedValue(3);
      await service.jobApplied(job, 'PAT-JOB-512');
      expect(fcmService.sendToUser).toHaveBeenCalledWith('p1', '3 caregivers applied', expect.any(String), { route: '/home' });
    });

    it('stays quiet for the rest of the burst', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'p1', role: 'individual' });
      jobApplicationsRepo.countAppliedSince.mockResolvedValue(2);
      await service.jobApplied(job, 'PAT-JOB-512');
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });

    it('never pushes about admin-posted jobs', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'a1', role: 'super_admin' });
      await service.jobApplied({ id: 'job-1', posted_by: 'a1' }, 'ADMIN-JOB-1');
      expect(jobApplicationsRepo.countAppliedSince).not.toHaveBeenCalled();
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });

    it('swallows failures so applying is never affected', async () => {
      usersRepo.findById.mockRejectedValue(new Error('db'));
      await expect(service.jobApplied(job, 'PAT-JOB-512')).resolves.toBeUndefined();
    });
  });

  describe('organisationRequirementApplied', () => {
    it('merges a burst the same way', async () => {
      orgApplicationsRepo.countAppliedSince.mockResolvedValue(1);
      orgApplicationsRepo.countApplied.mockResolvedValue(1);
      await service.organisationRequirementApplied({ id: 'r1', posted_by: 'o1' }, 'ORG-JOB-7');
      expect(fcmService.sendToUser).toHaveBeenCalledWith('o1', 'A caregiver applied', expect.any(String), { route: '/org-home' });
      fcmService.sendToUser.mockClear();
      orgApplicationsRepo.countAppliedSince.mockResolvedValue(4);
      await service.organisationRequirementApplied({ id: 'r1', posted_by: 'o1' }, 'ORG-JOB-7');
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });
  });

  describe('applicationDecided', () => {
    it('tells the caregiver they were accepted, opening MyJobs', async () => {
      await service.applicationDecided('c1', { accepted: true, displayId: 'PAT-JOB-512' });
      expect(fcmService.sendToUser).toHaveBeenCalledWith("c1", "You've been accepted", expect.stringContaining('PAT-JOB-512'), {
        route: '/caregiver/my-jobs',
      });
    });

    it('tells the caregiver they were declined, with the reason, opening Jobs', async () => {
      await service.applicationDecided('c1', { accepted: false, displayId: 'PAT-JOB-512', reason: 'Found someone closer' });
      expect(fcmService.sendToUser).toHaveBeenCalledWith('c1', 'Application update', expect.stringContaining('Found someone closer'), {
        route: '/caregiver/jobs',
      });
    });
  });

  describe('caregiverClosedEngagement', () => {
    it('tells a patient, and says the job is open again', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'p1', role: 'individual' });
      await service.caregiverClosedEngagement('p1', 'PAT-JOB-5', true);
      expect(fcmService.sendToUser).toHaveBeenCalledWith('p1', 'A caregiver closed the job', expect.stringContaining('open for new applicants again'), {
        route: '/home',
      });
    });

    it('tells an organisation, without claiming the requirement reopened', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'o1', role: 'organisation' });
      await service.caregiverClosedEngagement('o1', 'ORG-JOB-5', false);
      const call = fcmService.sendToUser.mock.calls[0];
      expect(call[2]).not.toContain('again');
      expect(call[3]).toEqual({ route: '/org-home' });
    });

    it('tells nobody for an admin-posted job', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'a1', role: 'super_admin' });
      await service.caregiverClosedEngagement('a1', 'ADMIN-JOB-5', true);
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });
  });

  describe('changes to a posting', () => {
    it('tells every applicant, sending an accepted caregiver to MyJobs and a waiting one to Jobs', async () => {
      jobApplicationsRepo.listApplicantUsers.mockResolvedValue([
        { user_id: 'c1', status: 'accepted' },
        { user_id: 'c2', status: 'applied' },
      ]);
      await service.jobUpdated('job-1', 'PAT-JOB-5');
      expect(jobApplicationsRepo.listApplicantUsers).toHaveBeenCalledWith('job-1', ['applied', 'accepted']);
      expect(fcmService.sendToUser).toHaveBeenCalledWith('c1', 'Job updated', expect.any(String), { route: '/caregiver/my-jobs' });
      expect(fcmService.sendToUser).toHaveBeenCalledWith('c2', 'Job updated', expect.any(String), { route: '/caregiver/jobs' });
    });

    it('does nothing when nobody has applied', async () => {
      jobApplicationsRepo.listApplicantUsers.mockResolvedValue([]);
      await service.jobUpdated('job-1', 'PAT-JOB-5');
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });

    it('tells organisation applicants about an edited requirement', async () => {
      orgApplicationsRepo.listApplicantUsers.mockResolvedValue([{ user_id: 'c1', status: 'applied' }]);
      await service.organisationRequirementUpdated('req-1', 'ORG-JOB-5');
      expect(orgApplicationsRepo.listApplicantUsers).toHaveBeenCalledWith('req-1', ['applied', 'accepted']);
      expect(fcmService.sendToUser).toHaveBeenCalledWith('c1', 'Job updated', expect.any(String), { route: '/caregiver/jobs' });
    });

    it('tells the caregivers it is given about a cancellation', async () => {
      await service.jobCancelled([{ user_id: 'c1', status: 'applied' }, { user_id: 'c2', status: 'accepted' }], 'PAT-JOB-5');
      expect(fcmService.sendToUser).toHaveBeenCalledTimes(2);
      expect(fcmService.sendToUser).toHaveBeenCalledWith('c2', 'Job cancelled', 'PAT-JOB-5 was cancelled by the employer.', {
        route: '/caregiver/jobs',
      });
    });

    it('tells only those still waiting when an organisation stops taking applications', async () => {
      orgApplicationsRepo.listApplicantUsers.mockResolvedValue([{ user_id: 'c1', status: 'applied' }]);
      await service.organisationRequirementNoLongerOpen('req-1', 'ORG-JOB-5');
      expect(orgApplicationsRepo.listApplicantUsers).toHaveBeenCalledWith('req-1', ['applied']);
      expect(fcmService.sendToUser).toHaveBeenCalledWith('c1', 'Job closed', expect.any(String), { route: '/caregiver/jobs' });
    });

    it('never fails the caller if sending throws', async () => {
      jobApplicationsRepo.listApplicantUsers.mockRejectedValue(new Error('db'));
      await expect(service.jobUpdated('job-1', 'PAT-JOB-5')).resolves.toBeUndefined();
    });
  });

  describe('account blocked / unblocked', () => {
    it('tells a patient posting is paused, with their home screen as the target', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'p1', role: 'individual' });
      await service.accountBlocked('p1', 'job_posting');
      expect(fcmService.sendToUser).toHaveBeenCalledWith('p1', 'Posting paused', expect.any(String), { route: '/home' });
    });

    it('tells an organisation it was fully blocked, and later restored', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'o1', role: 'organisation' });
      await service.accountBlocked('o1', 'full');
      await service.accountUnblocked('o1', 'full');
      expect(fcmService.sendToUser.mock.calls.map((c: any[]) => c[1])).toEqual(['Account blocked', 'Account restored']);
    });

    it('sends nothing for a caregiver or admin (they are not blocked this way)', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'c1', role: 'caregiver' });
      await service.accountBlocked('c1', 'full');
      expect(fcmService.sendToUser).not.toHaveBeenCalled();
    });
  });
});
