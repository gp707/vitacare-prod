import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { DatabaseModule } from './database/database.module';
import { EmailModule } from './email/email.module';
import { AuditModule } from './audit/audit.module';
import { FcmModule } from './fcm/fcm.module';
import { AuthModule } from './auth/auth.module';
import { CaregiverModule } from './caregiver/caregiver.module';
import { AdminModule } from './admin/admin.module';
import { JobsModule } from './jobs/jobs.module';
import { validateEnv } from './config/env.validation';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: validateEnv,
    }),
    DatabaseModule,
    EmailModule,
    AuditModule,
    FcmModule,
    AuthModule,
    CaregiverModule,
    AdminModule,
    JobsModule,
  ],
})
export class AppModule {}
