import { Controller, Get, Query } from '@nestjs/common';
import { AppConfigService } from './app-config.service';
import { MaintenanceCheckQueryDto } from './dto/maintenance-check-query.dto';

/** Public — no auth. Called by each app on every cold launch, alongside
 *  the version check (see AppVersionsController) — before login, so a
 *  user who's never logged in still gets blocked while maintenance is
 *  on. */
@Controller('app-maintenance')
export class AppMaintenanceController {
  constructor(private readonly appConfigService: AppConfigService) {}

  @Get('check')
  check(@Query() query: MaintenanceCheckQueryDto) {
    return this.appConfigService.checkMaintenance(query.app);
  }
}
