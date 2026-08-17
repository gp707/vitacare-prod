import { Module } from '@nestjs/common';
import { AppVersionsController } from './app-versions.controller';
import { AdminAppVersionsController } from './admin-app-versions.controller';
import { AppConfigService } from './app-config.service';

@Module({
  controllers: [AppVersionsController, AdminAppVersionsController],
  providers: [AppConfigService],
})
export class AppConfigModule {}
