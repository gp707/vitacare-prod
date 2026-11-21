import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AppConfigService } from './app-config.service';
import { VersionCheckQueryDto } from './dto/version-check-query.dto';
import { OptionalJwtAuthGuard } from '../common/guards/optional-jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';

/** Public — no auth. Called once on every cold launch by the single
 *  JustHeal binary (covers both the caregiver and patient/hospital
 *  flows), before the splash screen even loads the session, so a user
 *  who's never logged in still gets blocked on a too-old build. */
@Controller('app-versions')
export class AppVersionsController {
  constructor(private readonly appConfigService: AppConfigService) {}

  /** Open to everyone, but when the caller sends a valid token it is used to tell WHO is asking, so a
   *  minimum aimed at selected categories / accounts can be applied to them. No token, or a bad one, is
   *  just an anonymous caller — never an error (a broken check must never lock anyone out). */
  @Get('check')
  @UseGuards(OptionalJwtAuthGuard)
  check(@Query() query: VersionCheckQueryDto, @CurrentUser() user?: JwtPayload) {
    return this.appConfigService.checkVersion(query.platform, query.version, user?.sub ?? null);
  }
}
