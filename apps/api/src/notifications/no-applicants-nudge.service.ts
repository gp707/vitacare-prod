import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { OrganisationRequirementsRepository } from '../database/repositories/organisation-requirements.repository';
import { FcmService } from '../fcm/fcm.service';
import {
  NO_APPLICANTS_NUDGE_DAYS,
  inSendWindow,
  jobDisplayId,
  noApplicantsYet,
  organisationJobDisplayId,
} from './notification-templates';

/**
 * One gentle nudge to a patient or organisation whose requirement has been live
 * for 3 days and nobody has applied: "consider raising the salary / widening
 * your preferences". Sent once per posting (a reposted requirement counts its
 * own 3 days again), only 08:00–21:00 IST. Each nudge is claimed in the
 * database before sending, so running on several API instances can't double it.
 * Admin-posted jobs are never nudged: their poster has no app.
 */
@Injectable()
export class NoApplicantsNudgeService {
  private readonly logger = new Logger(NoApplicantsNudgeService.name);

  constructor(
    private readonly jobsRepo: JobsRepository,
    private readonly requirementsRepo: OrganisationRequirementsRepository,
    private readonly fcmService: FcmService,
  ) {}

  @Cron('*/30 * * * *', { timeZone: 'Asia/Kolkata' })
  async sweep(now: Date = new Date()): Promise<number> {
    if (!inSendWindow(now)) return 0;
    let sent = 0;
    try {
      for (const job of await this.jobsRepo.listNoApplicantNudgeCandidates(NO_APPLICANTS_NUDGE_DAYS)) {
        if (!(await this.jobsRepo.claimNoApplicantNudge(job.id))) continue;
        await this.send(job.posted_by, noApplicantsYet(jobDisplayId(job), false));
        sent++;
      }
      for (const requirement of await this.requirementsRepo.listNoApplicantNudgeCandidates(NO_APPLICANTS_NUDGE_DAYS)) {
        if (!(await this.requirementsRepo.claimNoApplicantNudge(requirement.id))) continue;
        await this.send(
          requirement.posted_by,
          noApplicantsYet(organisationJobDisplayId(requirement.requirement_number), true),
        );
        sent++;
      }
    } catch (error) {
      this.logger.error('No-applicants nudge sweep failed', error);
    }
    return sent;
  }

  private async send(userId: string, message: { title: string; body: string; route: string }): Promise<void> {
    try {
      await this.fcmService.sendToUser(userId, message.title, message.body, { route: message.route });
    } catch (error) {
      this.logger.error(`No-applicants nudge to ${userId} failed`, error);
    }
  }
}
