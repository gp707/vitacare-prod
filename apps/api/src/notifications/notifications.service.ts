import { Injectable, Logger } from '@nestjs/common';
import { UserRole } from '@vitacare/shared-constants';
import { JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { OrganisationRequirementApplicationsRepository } from '../database/repositories/organisation-requirement-applications.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { FcmService } from '../fcm/fcm.service';
import {
  BlockLevel,
  PushMessage,
  PushRoutes,
  accountBlocked,
  accountUnblocked,
  applicationAccepted,
  applicationDeclined,
  caregiverApplied,
  caregiverClosedEngagement,
  jobCancelled,
  jobNoLongerOpen,
  jobUpdated,
  requirementApproved,
  requirementRejected,
  welcomeCaregiver,
  welcomeIndividual,
  welcomeOrganisation,
} from './notification-templates';

/** A new account's first device registers within this long of the account
 *  being created -> treat it as "just registered" and welcome them. */
const WELCOME_WINDOW_MS = 10 * 60 * 1000;

/** Only the first applicant in this window is announced to the poster; the
 *  push itself carries the running total, so a burst is one notification. */
const APPLICANT_BURST_MINUTES = 10;

/**
 * The right push to the right person for each event. Every method is
 * best-effort: a notification failing must never fail (or slow down) the
 * action that triggered it, so errors are logged and swallowed. Recipients are
 * always accounts, never devices — FcmService fans out to that account's
 * devices.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly usersRepo: UsersRepository,
    private readonly fcmService: FcmService,
    private readonly jobApplicationsRepo: JobApplicationsRepository,
    private readonly orgApplicationsRepo: OrganisationRequirementApplicationsRepository,
  ) {}

  private async safe(what: string, fn: () => Promise<void>): Promise<void> {
    try {
      await fn();
    } catch (error) {
      this.logger.error(`Push "${what}" failed`, error);
    }
  }

  private send(userId: string, message: PushMessage): Promise<void> {
    return this.fcmService.sendToUser(userId, message.title, message.body, { route: message.route });
  }

  /** Home screen of a patient/organisation poster, or null for anyone who has
   *  no app (admins). */
  private posterRoute(role: string | undefined): string | null {
    if (role === UserRole.INDIVIDUAL) return PushRoutes.individualHome;
    if (role === UserRole.ORGANISATION) return PushRoutes.organisationHome;
    return null;
  }

  /**
   * Saves a device for an account and, if this is the first device of an
   * account created moments ago, sends the welcome push. Registration is the
   * moment a token first exists, so this is the earliest a "welcome" can be
   * delivered. Later logins on any device (including after a logout) are not
   * "new account" and get nothing.
   */
  async registerDevice(userId: string, token: string): Promise<void> {
    const [user, hadDevice] = await Promise.all([
      this.usersRepo.findById(userId),
      this.usersRepo.hasFcmToken(userId),
    ]);
    await this.usersRepo.updateFcmToken(userId, token);

    if (hadDevice || !user) return;
    if (Date.now() - new Date(user.created_at).getTime() > WELCOME_WINDOW_MS) return;
    const welcome =
      user.role === UserRole.CAREGIVER
        ? welcomeCaregiver()
        : user.role === UserRole.INDIVIDUAL
          ? welcomeIndividual()
          : user.role === UserRole.ORGANISATION
            ? welcomeOrganisation()
            : null;
    if (welcome) await this.safe('welcome', () => this.send(userId, welcome));
  }

  /** Admin approved a patient's or organisation's requirement. */
  async requirementApproved(posterUserId: string, displayId: string): Promise<void> {
    await this.safe('requirement approved', async () => {
      const poster = await this.usersRepo.findById(posterUserId);
      const route = this.posterRoute(poster?.role);
      if (route) await this.send(posterUserId, requirementApproved(displayId, route));
    });
  }

  async requirementRejected(posterUserId: string, displayId: string, reason: string | null): Promise<void> {
    await this.safe('requirement rejected', async () => {
      const poster = await this.usersRepo.findById(posterUserId);
      const route = this.posterRoute(poster?.role);
      if (route) await this.send(posterUserId, requirementRejected(displayId, reason, route));
    });
  }

  /** A caregiver applied to a job. Only patient-posted jobs have someone to
   *  tell — admin-posted jobs are managed in admin-web. */
  async jobApplied(job: { id: string; posted_by: string }, displayId: string): Promise<void> {
    await this.safe('job applied', async () => {
      const poster = await this.usersRepo.findById(job.posted_by);
      const route = this.posterRoute(poster?.role);
      if (!route) return;
      if ((await this.jobApplicationsRepo.countAppliedSince(job.id, APPLICANT_BURST_MINUTES)) !== 1) return;
      const total = await this.jobApplicationsRepo.countApplied(job.id);
      await this.send(job.posted_by, caregiverApplied(displayId, total, route));
    });
  }

  async organisationRequirementApplied(
    requirement: { id: string; posted_by: string },
    displayId: string,
  ): Promise<void> {
    await this.safe('requirement applied', async () => {
      if ((await this.orgApplicationsRepo.countAppliedSince(requirement.id, APPLICANT_BURST_MINUTES)) !== 1) return;
      const total = await this.orgApplicationsRepo.countApplied(requirement.id);
      await this.send(requirement.posted_by, caregiverApplied(displayId, total, PushRoutes.organisationHome));
    });
  }

  /** The poster (or admin) accepted or turned down a caregiver. */
  async applicationDecided(
    caregiverUserId: string,
    decision: { accepted: boolean; displayId: string; reason?: string | null },
  ): Promise<void> {
    await this.safe('application decided', () =>
      this.send(
        caregiverUserId,
        decision.accepted
          ? applicationAccepted(decision.displayId)
          : applicationDeclined(decision.displayId, decision.reason),
      ),
    );
  }

  // ── Changes to a posting, told to the caregivers it affects ─────────────

  private async toApplicants(
    applicants: { user_id: string; status: string }[],
    build: (accepted: boolean) => PushMessage,
  ): Promise<void> {
    await Promise.all(applicants.map((a) => this.send(a.user_id, build(a.status === 'accepted'))));
  }

  /** A caregiver closed their engagement; tell the patient/organisation. */
  async caregiverClosedEngagement(posterUserId: string, displayId: string, reopened: boolean): Promise<void> {
    await this.safe('caregiver closed engagement', async () => {
      const poster = await this.usersRepo.findById(posterUserId);
      const route = this.posterRoute(poster?.role);
      if (route) await this.send(posterUserId, caregiverClosedEngagement(displayId, reopened, route));
    });
  }

  /** A job was edited in a way applicants care about: everyone with an open or
   *  accepted application is told to re-check it. */
  async jobUpdated(jobId: string, displayId: string): Promise<void> {
    await this.safe('job updated', async () => {
      const applicants = await this.jobApplicationsRepo.listApplicantUsers(jobId, ['applied', 'accepted']);
      await this.toApplicants(applicants, (accepted) => jobUpdated(displayId, accepted));
    });
  }

  async organisationRequirementUpdated(requirementId: string, displayId: string): Promise<void> {
    await this.safe('requirement updated', async () => {
      const applicants = await this.orgApplicationsRepo.listApplicantUsers(requirementId, ['applied', 'accepted']);
      await this.toApplicants(applicants, (accepted) => jobUpdated(displayId, accepted));
    });
  }

  /** The caller looks the applicants up BEFORE the cancel (which rejects their
   *  applications), then passes them here. */
  async jobCancelled(applicants: { user_id: string; status: string }[], displayId: string): Promise<void> {
    await this.safe('job cancelled', () => this.toApplicants(applicants, () => jobCancelled(displayId)));
  }

  /** Admin closed a job, or an organisation stopped taking applications:
   *  those still waiting on an answer are told it is no longer open. */
  async jobNoLongerOpen(applicants: { user_id: string; status: string }[], displayId: string): Promise<void> {
    await this.safe('job closed', () => this.toApplicants(applicants, () => jobNoLongerOpen(displayId)));
  }

  async organisationRequirementNoLongerOpen(requirementId: string, displayId: string): Promise<void> {
    await this.safe('requirement closed', async () => {
      const waiting = await this.orgApplicationsRepo.listApplicantUsers(requirementId, ['applied']);
      await this.toApplicants(waiting, () => jobNoLongerOpen(displayId));
    });
  }

  // ── Admin blocked / unblocked an account ────────────────────────────────

  /** Awaited by the caller for a full block: a deactivated account receives no
   *  pushes, so this must be delivered before the account is switched off. */
  async accountBlocked(userId: string, level: BlockLevel): Promise<void> {
    await this.safe('account blocked', async () => {
      const user = await this.usersRepo.findById(userId);
      const route = this.posterRoute(user?.role);
      if (route) await this.send(userId, accountBlocked(level, route));
    });
  }

  async accountUnblocked(userId: string, level: BlockLevel): Promise<void> {
    await this.safe('account unblocked', async () => {
      const user = await this.usersRepo.findById(userId);
      const route = this.posterRoute(user?.role);
      if (route) await this.send(userId, accountUnblocked(level, route));
    });
  }
}
