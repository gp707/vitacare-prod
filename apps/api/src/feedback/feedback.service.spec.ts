import { canLeaveFeedback } from './feedback-eligibility';
import { FeedbackService } from './feedback.service';

const today = new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);
const day = (offset: number) => new Date(Date.now() + 5.5 * 3600 * 1000 + offset * 86400000).toISOString().slice(0, 10);

describe('canLeaveFeedback', () => {
  const base = { acceptedAt: new Date(), agreedStartDate: day(-3), hasPaidCycle: false, today };

  it('needs the caregiver to have been accepted', () => {
    expect(canLeaveFeedback({ ...base, acceptedAt: null })).toBe(false);
  });
  it('needs the work to have started: the cycle start date has arrived (today counts)', () => {
    expect(canLeaveFeedback(base)).toBe(true);
    expect(canLeaveFeedback({ ...base, agreedStartDate: today })).toBe(true);
    expect(canLeaveFeedback({ ...base, agreedStartDate: day(1) })).toBe(false);
  });
  it('accepted but no agreed start date yet is not enough', () => {
    expect(canLeaveFeedback({ ...base, agreedStartDate: null })).toBe(false);
  });
  it('a paid cycle proves the work started, even if the start date was later cleared', () => {
    expect(canLeaveFeedback({ ...base, agreedStartDate: null, hasPaidCycle: true })).toBe(true);
  });
  it('a paid cycle without ever being accepted does not qualify', () => {
    expect(canLeaveFeedback({ ...base, acceptedAt: null, hasPaidCycle: true })).toBe(false);
  });
});

describe('FeedbackService', () => {
  let service: FeedbackService;
  let feedbackRepo: any;
  let jobsRepo: any;
  let applicationsRepo: any;
  let profilesRepo: any;
  let usersRepo: any;
  let paymentsRepo: any;
  let auditService: any;
  let notificationsService: any;

  const application = (over: Record<string, unknown> = {}) => ({
    id: 'app-1',
    job_id: 'job-1',
    profile_id: 'prof-1',
    status: 'accepted',
    accepted_at: new Date(),
    agreed_start_date: day(-3),
    ...over,
  });

  beforeEach(() => {
    feedbackRepo = {
      listByApplication: jest.fn().mockResolvedValue([]),
      insert: jest.fn().mockResolvedValue(true),
      listForAdmin: jest.fn().mockResolvedValue({ items: [], total: 0 }),
    };
    jobsRepo = {
      findById: jest.fn().mockResolvedValue({ id: 'job-1', posted_by: 'patient-1', patient_job_number: 548, admin_job_number: null }),
    };
    applicationsRepo = {
      findById: jest.fn().mockResolvedValue(application()),
      findByJobAndProfile: jest.fn().mockResolvedValue(application()),
    };
    profilesRepo = {
      findFullById: jest.fn().mockResolvedValue({ id: 'prof-1', user_id: 'cg-user' }),
      findByUserId: jest.fn().mockResolvedValue({ id: 'prof-1' }),
    };
    usersRepo = { findById: jest.fn().mockResolvedValue({ id: 'patient-1', role: 'individual' }) };
    paymentsRepo = { listByApplication: jest.fn().mockResolvedValue([]) };
    auditService = { log: jest.fn() };
    notificationsService = { feedbackReceived: jest.fn() };
    service = new FeedbackService(
      feedbackRepo,
      jobsRepo,
      applicationsRepo,
      profilesRepo,
      usersRepo,
      paymentsRepo,
      auditService,
      notificationsService,
    );
  });

  describe('the patient/family', () => {
    it('may give feedback once the work has started', async () => {
      const state = await service.getForIndividual('patient-1', 'job-1', 'app-1');
      expect(state).toMatchObject({ can_give: true, reason: null, mine: null, received: null });
    });

    it('may not before the cycle start date has arrived', async () => {
      applicationsRepo.findById.mockResolvedValue(application({ agreed_start_date: day(2) }));
      const state = await service.getForIndividual('patient-1', 'job-1', 'app-1');
      expect(state).toMatchObject({ can_give: false, reason: 'not_started' });
    });

    it('cannot read or write about another patient\'s job', async () => {
      await expect(service.getForIndividual('someone-else', 'job-1', 'app-1')).rejects.toMatchObject({ code: 'GEN_002' });
      await expect(
        service.submitForIndividual('someone-else', 'job-1', 'app-1', { rating: 5 }, null),
      ).rejects.toMatchObject({ code: 'GEN_002' });
      expect(feedbackRepo.insert).not.toHaveBeenCalled();
    });

    it('cannot use an application that belongs to a different job', async () => {
      applicationsRepo.findById.mockResolvedValue(application({ job_id: 'other-job' }));
      await expect(service.getForIndividual('patient-1', 'job-1', 'app-1')).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('saves the feedback, audits it and tells the caregiver (no comment text in the push)', async () => {
      await service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 4, comment: 'Kind and punctual' }, '1.1.1.1');
      expect(feedbackRepo.insert).toHaveBeenCalledWith({
        application_id: 'app-1',
        author_role: 'individual',
        author_user_id: 'patient-1',
        about_user_id: 'cg-user',
        rating: 4,
        comment: 'Kind and punctual',
      });
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'feedback_submitted', userId: 'patient-1', targetUserId: 'cg-user', entityId: 'app-1' }),
      );
      expect(notificationsService.feedbackReceived).toHaveBeenCalledWith('cg-user', { toCaregiver: true, displayId: 'PAT-JOB-548' });
    });

    it('stores an empty comment as nothing', async () => {
      await service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 5, comment: '' }, null);
      expect(feedbackRepo.insert).toHaveBeenCalledWith(expect.objectContaining({ comment: null }));
    });

    it('FEEDBACK_001 when the work has not started, and nothing is saved or sent', async () => {
      applicationsRepo.findById.mockResolvedValue(application({ agreed_start_date: day(5) }));
      await expect(service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 5 }, null)).rejects.toMatchObject({
        code: 'FEEDBACK_001',
      });
      expect(feedbackRepo.insert).not.toHaveBeenCalled();
      expect(notificationsService.feedbackReceived).not.toHaveBeenCalled();
    });

    it('FEEDBACK_001 for a caregiver who was never accepted', async () => {
      applicationsRepo.findById.mockResolvedValue(application({ status: 'applied', accepted_at: null }));
      await expect(service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 5 }, null)).rejects.toMatchObject({
        code: 'FEEDBACK_001',
      });
    });

    it('still qualifies after the caregiver was rejected or closed duty, once the work had started', async () => {
      applicationsRepo.findById.mockResolvedValue(application({ status: 'rejected' }));
      await expect(service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 3 }, null)).resolves.toBeDefined();
    });

    it('FEEDBACK_002 when they already left one, with no second push', async () => {
      feedbackRepo.insert.mockResolvedValue(false);
      await expect(service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 5 }, null)).rejects.toMatchObject({
        code: 'FEEDBACK_002',
      });
      expect(notificationsService.feedbackReceived).not.toHaveBeenCalled();
      expect(auditService.log).not.toHaveBeenCalled();
    });

    it('once written it shows what they wrote and what the caregiver wrote about them, and can_give turns off', async () => {
      const created = new Date();
      feedbackRepo.listByApplication.mockResolvedValue([
        { author_role: 'individual', rating: 4, comment: 'Good', created_at: created },
        { author_role: 'caregiver', rating: 5, comment: 'Lovely family', created_at: created },
      ]);
      const state = await service.getForIndividual('patient-1', 'job-1', 'app-1');
      expect(state).toEqual({
        can_give: false,
        reason: null,
        mine: { rating: 4, comment: 'Good', created_at: created },
        received: { rating: 5, comment: 'Lovely family', created_at: created },
      });
    });
  });

  describe('the caregiver', () => {
    it('may give feedback about the family once the work has started', async () => {
      const state = await service.getForCaregiver('cg-user', 'job-1');
      expect(state).toMatchObject({ can_give: true });
    });

    it('saves it about the family and tells them', async () => {
      await service.submitForCaregiver('cg-user', 'job-1', { rating: 5, comment: 'Respectful' }, null);
      expect(feedbackRepo.insert).toHaveBeenCalledWith(
        expect.objectContaining({ author_role: 'caregiver', author_user_id: 'cg-user', about_user_id: 'patient-1', rating: 5 }),
      );
      expect(notificationsService.feedbackReceived).toHaveBeenCalledWith('patient-1', { toCaregiver: false, displayId: 'PAT-JOB-548' });
    });

    it('cannot write about a job they never applied to', async () => {
      applicationsRepo.findByJobAndProfile.mockResolvedValue(null);
      await expect(service.submitForCaregiver('cg-user', 'job-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('FEEDBACK_001 before the work has started', async () => {
      applicationsRepo.findByJobAndProfile.mockResolvedValue(application({ agreed_start_date: null }));
      await expect(service.submitForCaregiver('cg-user', 'job-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_001' });
    });

    it('an admin-posted job has no family to give feedback about', async () => {
      usersRepo.findById.mockResolvedValue({ id: 'admin-1', role: 'admin' });
      const state = await service.getForCaregiver('cg-user', 'job-1');
      expect(state).toMatchObject({ can_give: false, reason: 'no_family_account' });
      await expect(service.submitForCaregiver('cg-user', 'job-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_001' });
    });

    it('FEEDBACK_002 on a second attempt', async () => {
      feedbackRepo.insert.mockResolvedValue(false);
      await expect(service.submitForCaregiver('cg-user', 'job-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_002' });
    });

    it('sees what the family wrote about them as "received"', async () => {
      const created = new Date();
      feedbackRepo.listByApplication.mockResolvedValue([{ author_role: 'individual', rating: 2, comment: null, created_at: created }]);
      const state = await service.getForCaregiver('cg-user', 'job-1');
      expect(state.received).toEqual({ rating: 2, comment: null, created_at: created });
      expect(state.mine).toBeNull();
    });
  });

  describe('admin list', () => {
    it('passes the filters and paginates', async () => {
      feedbackRepo.listForAdmin.mockResolvedValue({ items: [{ id: 'f1' }], total: 41 });
      const result = await service.listForAdmin({ page: 2, limit: 20, author_role: 'caregiver', rating: 1, search: ' NUR-500 ' });
      expect(feedbackRepo.listForAdmin).toHaveBeenCalledWith(
        { author_role: 'caregiver', rating: 1, search: 'NUR-500' },
        { page: 2, limit: 20 },
      );
      expect(result.meta).toEqual({ page: 2, limit: 20, total: 41, totalPages: 3 });
    });
  });
});
