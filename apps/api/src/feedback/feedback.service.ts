import { Injectable } from '@nestjs/common';
import { AuditAction, UserRole } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { AuditService } from '../audit/audit.service';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import {
  EngagementFeedbackRepository,
  FeedbackAuthorRole,
  FeedbackRow,
} from '../database/repositories/engagement-feedback.repository';
import { JobApplicationRecord, JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { jobDisplayId } from '../notifications/notification-templates';
import { NotificationsService } from '../notifications/notifications.service';
import { ListFeedbackQueryDto } from './dto/list-feedback-query.dto';
import { SubmitFeedbackDto } from './dto/submit-feedback.dto';
import { canLeaveFeedback } from './feedback-eligibility';

/** Today's date on the IST calendar (YYYY-MM-DD). */
const istToday = (): string => new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);

export interface FeedbackView {
  rating: number;
  comment: string | null;
  created_at: Date;
}

/** Everything the signed-in person needs for one engagement. */
export interface FeedbackState {
  /** True while they may still write one: eligible and not yet written. */
  can_give: boolean;
  /** True when they wrote one and may still change it (patients/families and caregivers alike). */
  can_edit: boolean;
  /** Why not, when [can_give] is false and nothing was written yet. */
  reason: 'not_started' | 'no_family_account' | null;
  /** What this person wrote. */
  mine: FeedbackView | null;
  /** What the other side wrote about this person. */
  received: FeedbackView | null;
}

const view = (row: FeedbackRow | undefined): FeedbackView | null =>
  row ? { rating: row.rating, comment: row.comment, created_at: row.created_at } : null;

/**
 * Overall feedback between a patient/family and a caregiver, per engagement (one
 * caregiver on one job — never per salary cycle). Whether someone may write is
 * decided here, on the server, never by the app: see canLeaveFeedback. Write once
 * and final; each person sees only their own feedback and what was written about them.
 */
@Injectable()
export class FeedbackService {
  constructor(
    private readonly feedbackRepo: EngagementFeedbackRepository,
    private readonly jobsRepo: JobsRepository,
    private readonly applicationsRepo: JobApplicationsRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
    private readonly usersRepo: UsersRepository,
    private readonly auditService: AuditService,
    private readonly notificationsService: NotificationsService,
  ) {}

  // ── The patient/family's side ──────────────────────────────────────────

  async getForIndividual(userId: string, jobId: string, applicationId: string): Promise<FeedbackState> {
    const { application } = await this.loadIndividualEngagement(userId, jobId, applicationId);
    return this.stateFor(application, 'individual', true);
  }

  async submitForIndividual(
    userId: string,
    jobId: string,
    applicationId: string,
    dto: SubmitFeedbackDto,
    ipAddress: string | null,
  ) {
    const { job, application } = await this.loadIndividualEngagement(userId, jobId, applicationId);
    const caregiver = await this.profilesRepo.findFullById(application.profile_id);
    if (!caregiver) throw new AppException('JOB_006');
    await this.submit(application, 'individual', userId, caregiver.user_id, dto, ipAddress);
    void this.notificationsService.feedbackReceived(caregiver.user_id, { toCaregiver: true, displayId: jobDisplayId(job) });
    return { message: 'Thank you for your feedback', ...(await this.stateFor(application, 'individual', true)) };
  }

  /**
   * The patient/family changes the feedback they already wrote (rating and/or comment).
   * Allowed at any time and whatever the caregiver's status is now, since the engagement
   * was already eligible when they first wrote it. The caregiver sees the new version;
   * no second push is sent. The change is audit-logged with the previous rating.
   * FEEDBACK_003 when there is nothing of theirs to change.
   */
  async updateForIndividual(
    userId: string,
    jobId: string,
    applicationId: string,
    dto: SubmitFeedbackDto,
    ipAddress: string | null,
  ) {
    const { application } = await this.loadIndividualEngagement(userId, jobId, applicationId);
    await this.update(application, 'individual', userId, dto, ipAddress);
    return { message: 'Your feedback was updated', ...(await this.stateFor(application, 'individual', true)) };
  }

  // ── The caregiver's side ───────────────────────────────────────────────

  async getForCaregiver(userId: string, jobId: string): Promise<FeedbackState> {
    const { application, job } = await this.loadCaregiverEngagement(userId, jobId);
    return this.stateFor(application, 'caregiver', await this.hasFamilyAccount(job.posted_by));
  }

  async submitForCaregiver(userId: string, jobId: string, dto: SubmitFeedbackDto, ipAddress: string | null) {
    const { application, job } = await this.loadCaregiverEngagement(userId, jobId);
    // Only a job posted by a patient/family has someone to give feedback about.
    const hasFamily = await this.hasFamilyAccount(job.posted_by);
    if (!hasFamily) throw new AppException('FEEDBACK_001');
    await this.submit(application, 'caregiver', userId, job.posted_by, dto, ipAddress);
    void this.notificationsService.feedbackReceived(job.posted_by, { toCaregiver: false, displayId: jobDisplayId(job) });
    return { message: 'Thank you for your feedback', ...(await this.stateFor(application, 'caregiver', true)) };
  }

  /** The caregiver changes the feedback they already wrote about the family — same rules as the family's. */
  async updateForCaregiver(userId: string, jobId: string, dto: SubmitFeedbackDto, ipAddress: string | null) {
    const { application, job } = await this.loadCaregiverEngagement(userId, jobId);
    await this.update(application, 'caregiver', userId, dto, ipAddress);
    return {
      message: 'Your feedback was updated',
      ...(await this.stateFor(application, 'caregiver', await this.hasFamilyAccount(job.posted_by))),
    };
  }

  // ── Admin ──────────────────────────────────────────────────────────────

  async listForAdmin(query: ListFeedbackQueryDto) {
    const { items, total } = await this.feedbackRepo.listForAdmin(
      { author_role: query.author_role, rating: query.rating, search: query.search?.trim() || undefined },
      { page: query.page, limit: query.limit },
    );
    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };
    return { data: items, meta };
  }

  // ── Shared ─────────────────────────────────────────────────────────────

  private async loadIndividualEngagement(userId: string, jobId: string, applicationId: string) {
    const job = await this.jobsRepo.findById(jobId);
    if (!job || job.posted_by !== userId) throw new AppException('GEN_002');
    const application = await this.applicationsRepo.findById(applicationId);
    if (!application || application.job_id !== jobId) throw new AppException('JOB_006');
    return { job, application };
  }

  private async loadCaregiverEngagement(userId: string, jobId: string) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    const job = await this.jobsRepo.findById(jobId);
    if (!job) throw new AppException('GEN_002');
    const application = await this.applicationsRepo.findByJobAndProfile(jobId, profile.id);
    if (!application) throw new AppException('JOB_006');
    return { job, application };
  }

  /** A job posted by an admin has no patient/family to give feedback about. */
  private async hasFamilyAccount(postedBy: string): Promise<boolean> {
    const poster = await this.usersRepo.findById(postedBy);
    return poster?.role === UserRole.INDIVIDUAL;
  }

  private async eligible(application: JobApplicationRecord): Promise<boolean> {
    return canLeaveFeedback({
      acceptedAt: application.accepted_at,
      agreedStartDate: application.agreed_start_date,
      today: istToday(),
    });
  }

  private async stateFor(
    application: JobApplicationRecord,
    role: FeedbackAuthorRole,
    hasOtherParty: boolean,
  ): Promise<FeedbackState> {
    const rows = await this.feedbackRepo.listByApplication(application.id);
    const mine = view(rows.find((r) => r.author_role === role));
    const received = view(rows.find((r) => r.author_role !== role));
    const can_edit = mine != null;
    if (mine) return { can_give: false, can_edit, reason: null, mine, received };
    if (!hasOtherParty) return { can_give: false, can_edit, reason: 'no_family_account', mine, received };
    const ok = await this.eligible(application);
    return { can_give: ok, can_edit, reason: ok ? null : 'not_started', mine, received };
  }

  /** Replaces what [role]'s author already wrote on this engagement; FEEDBACK_003 when they wrote none. */
  private async update(
    application: JobApplicationRecord,
    role: FeedbackAuthorRole,
    authorUserId: string,
    dto: SubmitFeedbackDto,
    ipAddress: string | null,
  ) {
    const existing = (await this.feedbackRepo.listByApplication(application.id)).find((r) => r.author_role === role);
    if (!existing) throw new AppException('FEEDBACK_003');
    const comment = dto.comment && dto.comment.length > 0 ? dto.comment : null;
    if (!(await this.feedbackRepo.update(application.id, role, dto.rating, comment))) {
      throw new AppException('FEEDBACK_003');
    }
    await this.auditService.log({
      userId: authorUserId,
      targetUserId: existing.about_user_id,
      action: AuditAction.FEEDBACK_SUBMITTED,
      entityType: 'job_applications',
      entityId: application.id,
      beforeValue: { author_role: role, rating: existing.rating },
      afterValue: { author_role: role, rating: dto.rating, edited: true },
      ipAddress,
    });
  }

  private async submit(
    application: JobApplicationRecord,
    role: FeedbackAuthorRole,
    authorUserId: string,
    aboutUserId: string,
    dto: SubmitFeedbackDto,
    ipAddress: string | null,
  ) {
    if (!(await this.eligible(application))) throw new AppException('FEEDBACK_001');
    const comment = dto.comment && dto.comment.length > 0 ? dto.comment : null;
    const saved = await this.feedbackRepo.insert({
      application_id: application.id,
      author_role: role,
      author_user_id: authorUserId,
      about_user_id: aboutUserId,
      rating: dto.rating,
      comment,
    });
    if (!saved) throw new AppException('FEEDBACK_002');
    await this.auditService.log({
      userId: authorUserId,
      targetUserId: aboutUserId,
      action: AuditAction.FEEDBACK_SUBMITTED,
      entityType: 'job_applications',
      entityId: application.id,
      afterValue: { author_role: role, rating: dto.rating },
      ipAddress,
    });
  }
}
