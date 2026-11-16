import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { DailyPushClaimsRepository } from '../database/repositories/daily-push-claims.repository';
import { OrganisationRequirementsRepository } from '../database/repositories/organisation-requirements.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { FcmService } from '../fcm/fcm.service';
import { inSendWindow, newOrganisationJobsUpdate } from './notification-templates';

const DAY_MS = 24 * 60 * 60 * 1000;
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const CLAIM_KIND = 'new_organisation_jobs_update';

/**
 * Every day at 11:00 IST, tells caregivers how many hospital/rehab/clinic
 * requirements went live in the last 24 hours. The number is the real one, and
 * nothing is sent on a day when it is 0. Goes to ALL active caregiver accounts
 * with a registered device, whatever their verification status. The day is
 * claimed in the database before sending, so several API instances can't send
 * it twice. This is a daily summary; the instant "New Organisation Opening"
 * push when an admin approves a requirement is separate and unchanged.
 */
@Injectable()
export class DailyOrganisationJobsUpdateService {
  private readonly logger = new Logger(DailyOrganisationJobsUpdateService.name);

  constructor(
    private readonly requirementsRepo: OrganisationRequirementsRepository,
    private readonly usersRepo: UsersRepository,
    private readonly claimsRepo: DailyPushClaimsRepository,
    private readonly fcmService: FcmService,
  ) {}

  @Cron('0 11 * * *', { timeZone: 'Asia/Kolkata' })
  async run(now: Date = new Date()): Promise<number | null> {
    if (!inSendWindow(now)) return null;
    try {
      const count = await this.requirementsRepo.countLivePostedSince(new Date(now.getTime() - DAY_MS));
      if (count === 0) return null;

      const istDay = new Date(now.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
      if (!(await this.claimsRepo.claim(CLAIM_KIND, istDay, { count }))) return null;

      const tokens = await this.usersRepo.listAllCaregiverFcmTokens();
      const message = newOrganisationJobsUpdate(count);
      const sent = await this.fcmService.broadcastToTokens(tokens, message.title, message.body, {
        route: message.route,
      });
      this.logger.log(`Daily organisation jobs update sent (${count} new) to ${sent} caregiver devices`);
      return sent;
    } catch (error) {
      this.logger.error('Daily organisation jobs update failed', error);
      return null;
    }
  }
}
