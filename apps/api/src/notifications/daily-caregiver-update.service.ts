import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { UserRole } from '@vitacare/shared-constants';
import { DailyPushClaimsRepository } from '../database/repositories/daily-push-claims.repository';
import { UsersRepository } from '../database/repositories/users.repository';
import { FcmService } from '../fcm/fcm.service';
import { NEW_CAREGIVERS_DISPLAY_BONUS, inSendWindow, newCaregiversUpdate } from './notification-templates';

const DAY_MS = 24 * 60 * 60 * 1000;
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const CLAIM_KIND = 'new_caregivers_update';

/**
 * Every day at 10:00 IST, tells every patient/family and organisation how many
 * caregivers joined in the last 24 hours, so an account with no live
 * requirement still hears from JustHeal. Sent to ALL active individual and
 * organisation accounts that have a registered device.
 *
 * The number shown is the real count plus NEW_CAREGIVERS_DISPLAY_BONUS (a
 * deliberate product decision, see notification-templates.ts). The day is
 * claimed in the database before sending, so several API instances (or a
 * restart at 10:00) can't send it twice.
 */
@Injectable()
export class DailyCaregiverUpdateService {
  private readonly logger = new Logger(DailyCaregiverUpdateService.name);

  constructor(
    private readonly usersRepo: UsersRepository,
    private readonly claimsRepo: DailyPushClaimsRepository,
    private readonly fcmService: FcmService,
  ) {}

  @Cron('0 10 * * *', { timeZone: 'Asia/Kolkata' })
  async run(now: Date = new Date()): Promise<{ individuals: number; organisations: number } | null> {
    if (!inSendWindow(now)) return null;
    try {
      const realCount = await this.usersRepo.countCaregiversRegisteredSince(new Date(now.getTime() - DAY_MS));
      const displayedCount = realCount + NEW_CAREGIVERS_DISPLAY_BONUS;
      const istDay = new Date(now.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);

      if (!(await this.claimsRepo.claim(CLAIM_KIND, istDay, { real_count: realCount, displayed_count: displayedCount }))) {
        return null;
      }

      const [individualTokens, organisationTokens] = await Promise.all([
        this.usersRepo.listFcmTokensByRole(UserRole.INDIVIDUAL),
        this.usersRepo.listFcmTokensByRole(UserRole.ORGANISATION),
      ]);
      const individual = newCaregiversUpdate(displayedCount, false);
      const organisation = newCaregiversUpdate(displayedCount, true);
      const individuals = await this.fcmService.broadcastToTokens(individualTokens, individual.title, individual.body, {
        route: individual.route,
      });
      const organisations = await this.fcmService.broadcastToTokens(
        organisationTokens,
        organisation.title,
        organisation.body,
        { route: organisation.route },
      );
      this.logger.log(
        `Daily caregiver update sent (real ${realCount}, shown ${displayedCount}) to ${individuals} patient and ${organisations} organisation devices`,
      );
      return { individuals, organisations };
    } catch (error) {
      this.logger.error('Daily caregiver update failed', error);
      return null;
    }
  }
}
