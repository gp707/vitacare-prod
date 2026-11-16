import { Global, Module } from '@nestjs/common';
import { DutyRemindersService } from './duty-reminders.service';
import { DailyCaregiverUpdateService } from './daily-caregiver-update.service';
import { DailyPatientUpdateService } from './daily-patient-update.service';
import { NoApplicantsNudgeService } from './no-applicants-nudge.service';
import { NotificationsService } from './notifications.service';

@Global()
@Module({
  providers: [NotificationsService, DutyRemindersService, NoApplicantsNudgeService, DailyCaregiverUpdateService, DailyPatientUpdateService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
