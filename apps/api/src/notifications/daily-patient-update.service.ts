import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { DailyPushClaimsRepository } from '../database/repositories/daily-push-claims.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { FcmService } from '../fcm/fcm.service';
import { inSendWindow, newPatientsUpdate } from './notification-templates';

const DAY_MS = 24 * 60 * 60 * 1000;
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const CLAIM_KIND = 'new_patients_update';

/**
 * Every day at 10:30 IST, tells caregivers how many patients/families joined in
 * the last 24 hours. The number is the real one, and nothing is sent on a day
 * when it is 0. Goes to ALL active caregiver accounts with a registered device,
 * whatever their verification status. The day is claimed in the
 * database before sending, so several API instances can't send it twice.
 */
@Injectable()
export class DailyPatientUpdateService {
  private readonly logger = new Logger(DailyPatientUpdateService.name);

  constructor(
    private readonly usersRepo: UsersRepository,
    private readonly claimsRepo: DailyPushClaimsRepository,
    private readonly fcmService: FcmService,
  ) {}

  @Cron('30 10 * * *', { timeZone: 'Asia/Kolkata' })
  async run(now: Date = new Date()): Promise<number | null> {
    if (!inSendWindow(now)) return null;
    try {
      const count = await this.usersRepo.countIndividualsRegisteredSince(new Date(now.getTime() - DAY_MS));
      if (count === 0) return null;

      const istDay = new Date(now.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
      if (!(await this.claimsRepo.claim(CLAIM_KIND, istDay, { count }))) return null;

      const tokens = await this.usersRepo.listAllCaregiverFcmTokens();
      const message = newPatientsUpdate(count);
      const sent = await this.fcmService.broadcastToTokens(tokens, message.title, message.body, {
        route: message.route,
      });
      this.logger.log(`Daily patient update sent (${count} new patients) to ${sent} caregiver devices`);
      return sent;
    } catch (error) {
      this.logger.error('Daily patient update failed', error);
      return null;
    }
  }
}
