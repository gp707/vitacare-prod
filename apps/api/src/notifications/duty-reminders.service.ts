import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { DutyReminderCandidate, JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { FcmService } from '../fcm/fcm.service';
import {
  DutyReminderStage,
  dutyReminder,
  dutyReminderStage,
  dutyStartAt,
  jobDisplayId,
  shouldDefer,
} from './notification-templates';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * "You need to go to work in 2 days" / "in 1 day" / "soon — do not forget"
 * for caregivers with an accepted job. Runs every 15 minutes; each reminder is
 * claimed in the database before sending (claimDutyReminder), so several API
 * instances can run it without double-sending, and each one is sent once per
 * acceptance. Routine reminders only go out 08:00–21:00 IST.
 *
 * Only jobs carry a start date; organisation requirements have none (they use
 * the organisation's own schedule), so they get no duty reminders.
 */
@Injectable()
export class DutyRemindersService {
  private readonly logger = new Logger(DutyRemindersService.name);

  constructor(
    private readonly applicationsRepo: JobApplicationsRepository,
    private readonly fcmService: FcmService,
  ) {}

  @Cron('*/15 * * * *', { timeZone: 'Asia/Kolkata' })
  async sweep(now: Date = new Date()): Promise<number> {
    let sent = 0;
    try {
      // Duty starts within 48h at most; one extra day either side absorbs the
      // IST/UTC date boundary. The exact stage comes from the time left.
      const from = new Date(now.getTime() - DAY_MS).toISOString().slice(0, 10);
      const to = new Date(now.getTime() + 3 * DAY_MS).toISOString().slice(0, 10);
      const candidates = await this.applicationsRepo.listAcceptedStartingBetween(from, to);
      for (const candidate of candidates) {
        if (await this.remind(candidate, now)) sent++;
      }
    } catch (error) {
      this.logger.error('Duty reminder sweep failed', error);
    }
    return sent;
  }

  private alreadySent(candidate: DutyReminderCandidate, stage: DutyReminderStage): boolean {
    return stage === '12h'
      ? candidate.duty_reminder_12h_at != null
      : stage === '1d'
        ? candidate.duty_reminder_1d_at != null
        : candidate.duty_reminder_2d_at != null;
  }

  private async remind(candidate: DutyReminderCandidate, now: Date): Promise<boolean> {
    const startAt = dutyStartAt(candidate.start_date, candidate.duty_type);
    const stage = dutyReminderStage(startAt.getTime() - now.getTime());
    if (!stage || this.alreadySent(candidate, stage)) return false;
    if (shouldDefer(now, stage, startAt)) return false;
    // Take ownership first: if another instance already did, send nothing.
    if (!(await this.applicationsRepo.claimDutyReminder(candidate.application_id, stage))) return false;

    const message = dutyReminder(stage, {
      display_id: jobDisplayId(candidate),
      area: candidate.area,
      city: candidate.city,
    });
    try {
      await this.fcmService.sendToUser(candidate.user_id, message.title, message.body, { route: message.route });
    } catch (error) {
      this.logger.error(`Duty reminder (${stage}) failed for application ${candidate.application_id}`, error);
    }
    return true;
  }
}
