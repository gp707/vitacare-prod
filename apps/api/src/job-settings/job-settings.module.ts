import { Module } from '@nestjs/common';
import { JobSettingsController } from './job-settings.controller';
import { AdminJobSettingsController } from './admin-job-settings.controller';
import { JobSettingsService } from './job-settings.service';

@Module({
  controllers: [JobSettingsController, AdminJobSettingsController],
  providers: [JobSettingsService],
})
export class JobSettingsModule {}
