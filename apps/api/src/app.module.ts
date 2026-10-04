import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { DatabaseModule } from './database/database.module';
import { EmailModule } from './email/email.module';
import { AuditModule } from './audit/audit.module';
import { FcmModule } from './fcm/fcm.module';
import { AuthModule } from './auth/auth.module';
import { CaregiverModule } from './caregiver/caregiver.module';
import { AdminModule } from './admin/admin.module';
import { JobsModule } from './jobs/jobs.module';
import { AdminBulkDeleteModule } from './admin-bulk-delete/admin-bulk-delete.module';
import { IndividualModule } from './individual/individual.module';
import { OrganisationModule } from './organisation/organisation.module';
import { AppConfigModule } from './app-config/app-config.module';
import { OtpModule } from './otp/otp.module';
import { RateCardModule } from './rate-card/rate-card.module';
import { ScopeOfWorkModule } from './scope-of-work/scope-of-work.module';
import { DutyRequirementsModule } from './duty-requirements/duty-requirements.module';
import { JobSettingsModule } from './job-settings/job-settings.module';
import { IndividualMessagesModule } from './individual-messages/individual-messages.module';
import { CaregiverMessagesModule } from './caregiver-messages/caregiver-messages.module';
import { AuditLogRetentionModule } from './audit-log-retention/audit-log-retention.module';
import { AdminPushNotificationsModule } from './admin-push-notifications/admin-push-notifications.module';
import { TicketsModule } from './tickets/tickets.module';
import { validateEnv } from './config/env.validation';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: validateEnv,
    }),
    ScheduleModule.forRoot(),
    DatabaseModule,
    EmailModule,
    AuditModule,
    FcmModule,
    AuthModule,
    CaregiverModule,
    AdminModule,
    JobsModule,
    AdminBulkDeleteModule,
    IndividualModule,
    OrganisationModule,
    AppConfigModule,
    OtpModule,
    RateCardModule,
    ScopeOfWorkModule,
    DutyRequirementsModule,
    JobSettingsModule,
    IndividualMessagesModule,
    CaregiverMessagesModule,
    AuditLogRetentionModule,
    AdminPushNotificationsModule,
    TicketsModule,
  ],
})
export class AppModule {}
