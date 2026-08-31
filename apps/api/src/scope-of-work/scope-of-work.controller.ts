import { Controller, Get } from '@nestjs/common';
import { ScopeOfWorkService } from './scope-of-work.service';

/** Public — no auth. Caregiver-app fetches this fresh on every "Scope of
 *  Work" tap and shows only the bullet list for the tier that job's
 *  care_receiver derives to (see care_tier.dart). */
@Controller('scope-of-work')
export class ScopeOfWorkController {
  constructor(private readonly scopeOfWorkService: ScopeOfWorkService) {}

  @Get()
  get() {
    return this.scopeOfWorkService.get();
  }
}
