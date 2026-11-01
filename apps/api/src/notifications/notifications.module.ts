import { Global, Module } from '@nestjs/common';
import { DutyRemindersService } from './duty-reminders.service';
import { NoApplicantsNudgeService } from './no-applicants-nudge.service';
import { NotificationsService } from './notifications.service';

@Global()
@Module({
  providers: [NotificationsService, DutyRemindersService, NoApplicantsNudgeService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
