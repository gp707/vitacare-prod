import { Module } from '@nestjs/common';
import { AppVersionsController } from './app-versions.controller';
import { AdminAppVersionsController } from './admin-app-versions.controller';
import { AppMaintenanceController } from './app-maintenance.controller';
import { AdminAppMaintenanceController } from './admin-app-maintenance.controller';
import { AppConfigService } from './app-config.service';
import { AdminAccountSearchController } from './admin-account-search.controller';
import { OptionalJwtAuthGuard } from '../common/guards/optional-jwt-auth.guard';

@Module({
  controllers: [
    AppVersionsController,
    AdminAppVersionsController,
    AppMaintenanceController,
    AdminAppMaintenanceController,
    AdminAccountSearchController,
  ],
  providers: [AppConfigService, OptionalJwtAuthGuard],
})
export class AppConfigModule {}
