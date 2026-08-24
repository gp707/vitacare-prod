import { Controller, Get, Query } from '@nestjs/common';
import { OtpSettingsService } from './otp-settings.service';
import { OtpSettingsQueryDto } from './dto/otp-settings-query.dto';

/** Public — no auth. Called by caregiver-app/nursenow-app before rendering
 *  registration/login UI, so an unauthenticated caller can know which
 *  fields to show. Clients wrap this in try/catch and fail open to
 *  `false` (PIN mode, the known-safe unchanged default) on any error. */
@Controller('auth/otp-settings')
export class OtpSettingsController {
  constructor(private readonly otpSettingsService: OtpSettingsService) {}

  @Get()
  check(@Query() query: OtpSettingsQueryDto) {
    return this.otpSettingsService.isEnabled(query.app);
  }
}
