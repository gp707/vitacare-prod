import { Controller, Get } from '@nestjs/common';
import { AppConfigService } from './app-config.service';

/** Public — no auth. Called once on every cold launch by the single
 *  JustHeal binary, alongside the version check (see
 *  AppVersionsController) — before login, so a user who's never logged in
 *  still gets blocked while maintenance is on. */
@Controller('app-maintenance')
export class AppMaintenanceController {
  constructor(private readonly appConfigService: AppConfigService) {}

  @Get('check')
  check() {
    return this.appConfigService.checkMaintenance();
  }
}
