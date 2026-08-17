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
import { AppConfigModule } from './app-config/app-config.module';
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
    AppConfigModule,
  ],
})
export class AppModule {}
