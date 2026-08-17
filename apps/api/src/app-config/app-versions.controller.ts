import { Controller, Get, Query } from '@nestjs/common';
import { AppConfigService } from './app-config.service';
import { VersionCheckQueryDto } from './dto/version-check-query.dto';

/** Public — no auth. Called by the caregiver app on every cold launch,
 *  before the splash screen even loads the session, so a caregiver who's
 *  never logged in still gets blocked on a too-old build. */
@Controller('app-versions')
export class AppVersionsController {
  constructor(private readonly appConfigService: AppConfigService) {}

  @Get('check')
  check(@Query() query: VersionCheckQueryDto) {
    return this.appConfigService.checkVersion(query.platform, query.version);
  }
}
