import { Module } from '@nestjs/common';
import { AppVersionsController } from './app-versions.controller';
import { AdminAppVersionsController } from './admin-app-versions.controller';
import { AppMaintenanceController } from './app-maintenance.controller';
import { AdminAppMaintenanceController } from './admin-app-maintenance.controller';
import { AppConfigService } from './app-config.service';

@Module({
  controllers: [
    AppVersionsController,
    AdminAppVersionsController,
    AppMaintenanceController,
    AdminAppMaintenanceController,
  ],
  providers: [AppConfigService],
})
export class AppConfigModule {}
