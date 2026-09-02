import { Controller, Get } from '@nestjs/common';
import { JobSettingsService } from './job-settings.service';

/** Public — no auth. Currently exposes just apply_by_window_days (the
 *  caregiver-facing "apply-by" urgency window on a job), fetched once by
 *  caregiver-app (e.g. at splash) rather than assuming the old hardcoded
 *  3-day constant. */
@Controller('job-settings')
export class JobSettingsController {
  constructor(private readonly jobSettingsService: JobSettingsService) {}

  @Get()
  get() {
    return this.jobSettingsService.get();
  }
}
