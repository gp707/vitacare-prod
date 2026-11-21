import { canLeaveFeedback } from './feedback-eligibility';
import { FeedbackService } from './feedback.service';

const today = new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);
const day = (offset: number) => new Date(Date.now() + 5.5 * 3600 * 1000 + offset * 86400000).toISOString().slice(0, 10);

describe('canLeaveFeedback', () => {
  const base = { acceptedAt: new Date(), agreedStartDate: day(-3), today };

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
});

describe('FeedbackService', () => {
  let service: FeedbackService;
  let feedbackRepo: any;
  let jobsRepo: any;
  let applicationsRepo: any;
  let profilesRepo: any;
  let usersRepo: any;
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
      update: jest.fn().mockResolvedValue(true),
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
    auditService = { log: jest.fn() };
    notificationsService = { feedbackReceived: jest.fn() };
    service = new FeedbackService(
      feedbackRepo,
      jobsRepo,
      applicationsRepo,
      profilesRepo,
      usersRepo,
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
      expect(notificationsService.feedbackReceived).toHaveBeenCalledWith('cg-user', { displayId: 'PAT-JOB-548', rating: 4 });
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

    it('once written it shows only what the patient wrote — never what the caregiver wrote about them — and can_give turns off', async () => {
      const created = new Date();
      feedbackRepo.listByApplication.mockResolvedValue([
        { author_role: 'individual', rating: 4, comment: 'Good', created_at: created },
        { author_role: 'caregiver', rating: 5, comment: 'Lovely family', created_at: created },
      ]);
      const state = await service.getForIndividual('patient-1', 'job-1', 'app-1');
      expect(state).toEqual({
        can_give: false,
        can_edit: true,
        reason: null,
        mine: { rating: 4, comment: 'Good', created_at: created },
        received: null,
      });
    });

    it('never shows the caregiver\'s feedback to the patient, even before the patient wrote their own', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([
        { author_role: 'caregiver', rating: 1, comment: 'Secret', created_at: new Date() },
      ]);
      const state = await service.getForIndividual('patient-1', 'job-1', 'app-1');
      expect(state.received).toBeNull();
      expect(JSON.stringify(state)).not.toContain('Secret');
    });
  });

  describe('the patient/family changing their feedback', () => {
    const created = new Date('2026-11-20T10:00:00Z');
    const mine = { author_role: 'individual', author_user_id: 'patient-1', about_user_id: 'cg-user', rating: 3, comment: 'Ok', created_at: created };

    it('replaces the rating and comment, audit-logs the old and new rating, and sends no second push', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      const result = await service.updateForIndividual('patient-1', 'job-1', 'app-1', { rating: 5, comment: 'Much better now' }, '1.1.1.1');
      expect(feedbackRepo.update).toHaveBeenCalledWith('app-1', 'individual', 5, 'Much better now');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'feedback_submitted',
          userId: 'patient-1',
          targetUserId: 'cg-user',
          beforeValue: { author_role: 'individual', rating: 3 },
          afterValue: { author_role: 'individual', rating: 5, edited: true },
        }),
      );
      expect(notificationsService.feedbackReceived).not.toHaveBeenCalled();
      expect(result.message).toBe('Your feedback was updated');
    });

    it('can clear the comment, keeping the stars', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      await service.updateForIndividual('patient-1', 'job-1', 'app-1', { rating: 4, comment: '' }, null);
      expect(feedbackRepo.update).toHaveBeenCalledWith('app-1', 'individual', 4, null);
    });

    it('still works after the caregiver was rejected or closed duty (it was eligible when first written)', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      applicationsRepo.findById.mockResolvedValue(application({ status: 'rejected', agreed_start_date: null }));
      await expect(service.updateForIndividual('patient-1', 'job-1', 'app-1', { rating: 2 }, null)).resolves.toBeDefined();
    });

    it('FEEDBACK_003 when they have not written one yet (use the normal send instead)', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([]);
      await expect(service.updateForIndividual('patient-1', 'job-1', 'app-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_003' });
      expect(feedbackRepo.update).not.toHaveBeenCalled();
    });

    it('cannot change someone else\'s feedback on another patient\'s job', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      await expect(service.updateForIndividual('someone-else', 'job-1', 'app-1', { rating: 1 }, null)).rejects.toMatchObject({ code: 'GEN_002' });
      expect(feedbackRepo.update).not.toHaveBeenCalled();
    });

    it('only changes the patient\'s own feedback, never what the caregiver wrote about them', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([{ ...mine, author_role: 'caregiver' }]);
      await expect(service.updateForIndividual('patient-1', 'job-1', 'app-1', { rating: 1 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_003' });
    });

    it('the state tells the app it can edit once something was written, and not before', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      expect((await service.getForIndividual('patient-1', 'job-1', 'app-1')).can_edit).toBe(true);
      feedbackRepo.listByApplication.mockResolvedValue([]);
      expect((await service.getForIndividual('patient-1', 'job-1', 'app-1')).can_edit).toBe(false);
    });
  });

  describe('the caregiver changing their feedback', () => {
    const created = new Date('2026-11-20T10:00:00Z');
    const mine = { author_role: 'caregiver', author_user_id: 'cg-user', about_user_id: 'patient-1', rating: 4, comment: 'Good', created_at: created };

    it('replaces the rating and comment, audit-logs it, and sends no second push', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      const result = await service.updateForCaregiver('cg-user', 'job-1', { rating: 2, comment: 'Things changed' }, '1.1.1.1');
      expect(feedbackRepo.update).toHaveBeenCalledWith('app-1', 'caregiver', 2, 'Things changed');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'feedback_submitted',
          userId: 'cg-user',
          targetUserId: 'patient-1',
          beforeValue: { author_role: 'caregiver', rating: 4 },
          afterValue: { author_role: 'caregiver', rating: 2, edited: true },
        }),
      );
      expect(notificationsService.feedbackReceived).not.toHaveBeenCalled();
      expect(result).toMatchObject({ message: 'Your feedback was updated', can_edit: true });
    });

    it('can clear the comment', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      await service.updateForCaregiver('cg-user', 'job-1', { rating: 5, comment: '' }, null);
      expect(feedbackRepo.update).toHaveBeenCalledWith('app-1', 'caregiver', 5, null);
    });

    it('FEEDBACK_003 when they have not written one yet', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([]);
      await expect(service.updateForCaregiver('cg-user', 'job-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_003' });
      expect(feedbackRepo.update).not.toHaveBeenCalled();
    });

    it('only ever changes their own, never what the family wrote about them', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([{ ...mine, author_role: 'individual' }]);
      await expect(service.updateForCaregiver('cg-user', 'job-1', { rating: 1 }, null)).rejects.toMatchObject({ code: 'FEEDBACK_003' });
    });

    it('cannot change feedback on a job they never applied to', async () => {
      applicationsRepo.findByJobAndProfile.mockResolvedValue(null);
      await expect(service.updateForCaregiver('cg-user', 'job-1', { rating: 5 }, null)).rejects.toMatchObject({ code: 'JOB_006' });
    });

    it('still works after they were rejected or closed duty', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      applicationsRepo.findByJobAndProfile.mockResolvedValue(application({ status: 'completed', agreed_start_date: null }));
      await expect(service.updateForCaregiver('cg-user', 'job-1', { rating: 3 }, null)).resolves.toBeDefined();
    });

    it('the state tells the app it can edit', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([mine]);
      expect((await service.getForCaregiver('cg-user', 'job-1')).can_edit).toBe(true);
    });
  });

  describe('the caregiver', () => {
    it('may give feedback about the family once the work has started', async () => {
      const state = await service.getForCaregiver('cg-user', 'job-1');
      expect(state).toMatchObject({ can_give: true });
    });

    it('saves it about the family and does NOT tell them (no push to the patient)', async () => {
      await service.submitForCaregiver('cg-user', 'job-1', { rating: 5, comment: 'Respectful' }, null);
      expect(feedbackRepo.insert).toHaveBeenCalledWith(
        expect.objectContaining({ author_role: 'caregiver', author_user_id: 'cg-user', about_user_id: 'patient-1', rating: 5 }),
      );
      expect(notificationsService.feedbackReceived).not.toHaveBeenCalled();
    });

    it('a patient\'s feedback about the caregiver still tells the caregiver', async () => {
      await service.submitForIndividual('patient-1', 'job-1', 'app-1', { rating: 4 }, null);
      expect(notificationsService.feedbackReceived).toHaveBeenCalledTimes(1);
      expect(notificationsService.feedbackReceived).toHaveBeenCalledWith('cg-user', { displayId: 'PAT-JOB-548', rating: 4 });
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

    it('sees the family\'s STAR RATING about them as "received"', async () => {
      const created = new Date();
      feedbackRepo.listByApplication.mockResolvedValue([{ author_role: 'individual', rating: 2, comment: null, created_at: created }]);
      const state = await service.getForCaregiver('cg-user', 'job-1');
      expect(state.received).toEqual({ rating: 2, comment: null, created_at: created });
      expect(state.mine).toBeNull();
    });

    it('never gets the written comment: the stars come through, the comment is always null', async () => {
      const created = new Date();
      feedbackRepo.listByApplication.mockResolvedValue([
        { author_role: 'individual', rating: 4, comment: 'She was late twice', created_at: created },
        { author_role: 'caregiver', rating: 5, comment: 'My own note', created_at: created },
      ]);
      const state = await service.getForCaregiver('cg-user', 'job-1');
      expect(state.received).toEqual({ rating: 4, comment: null, created_at: created });
      expect(JSON.stringify(state)).not.toContain('She was late twice');
      // their own feedback, comment included, is theirs to see
      expect(state.mine).toEqual({ rating: 5, comment: 'My own note', created_at: created });
    });

    it('the response to their own submit does not leak the comment either', async () => {
      feedbackRepo.listByApplication.mockResolvedValue([
        { author_role: 'individual', rating: 3, comment: 'Private comment', created_at: new Date() },
        { author_role: 'caregiver', rating: 5, comment: null, created_at: new Date() },
      ]);
      const result = await service.submitForCaregiver('cg-user', 'job-1', { rating: 5 }, null);
      expect(JSON.stringify(result)).not.toContain('Private comment');
    });
  });

  describe('admin correcting a feedback', () => {
    const before = {
      application_id: 'app-1',
      author_role: 'individual',
      author_user_id: 'patient-1',
      about_user_id: 'cg-user',
      old_rating: 2,
    };
    beforeEach(() => {
      feedbackRepo.updateById = jest.fn().mockResolvedValue(before);
    });

    it('replaces the rating and comment, audit-logs the old rating against the person it is about, and notifies nobody', async () => {
      const result = await service.updateForAdmin('admin-1', 'f1', { rating: 4, comment: 'Corrected' }, '1.1.1.1');
      expect(feedbackRepo.updateById).toHaveBeenCalledWith('f1', 4, 'Corrected');
      expect(auditService.log).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'admin-1',
          targetUserId: 'cg-user',
          action: 'feedback_submitted',
          entityId: 'app-1',
          beforeValue: { author_role: 'individual', rating: 2 },
          afterValue: { author_role: 'individual', rating: 4, edited_by_admin: true },
        }),
      );
      expect(notificationsService.feedbackReceived).not.toHaveBeenCalled();
      expect(result).toMatchObject({ id: 'f1', rating: 4, comment: 'Corrected' });
    });

    it('an empty comment clears it', async () => {
      await service.updateForAdmin('admin-1', 'f1', { rating: 3, comment: '' }, null);
      expect(feedbackRepo.updateById).toHaveBeenCalledWith('f1', 3, null);
    });

    it('works on a caregiver-written feedback too', async () => {
      feedbackRepo.updateById.mockResolvedValue({ ...before, author_role: 'caregiver', author_user_id: 'cg-user', about_user_id: 'patient-1' });
      await service.updateForAdmin('admin-1', 'f2', { rating: 1 }, null);
      expect(auditService.log).toHaveBeenCalledWith(expect.objectContaining({ targetUserId: 'patient-1' }));
    });

    it('GEN_002 when the feedback does not exist, and nothing is logged', async () => {
      feedbackRepo.updateById.mockResolvedValue(null);
      await expect(service.updateForAdmin('admin-1', 'nope', { rating: 3 }, null)).rejects.toMatchObject({ code: 'GEN_002' });
      expect(auditService.log).not.toHaveBeenCalled();
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
