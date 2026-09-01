import { Controller, Get } from '@nestjs/common';
import { DutyRequirementsService } from './duty-requirements.service';

/** Public — no auth. nursenow-app fetches this fresh on every "Hours Care
 *  Needed" info-button tap and shows only the list for whichever shift is
 *  currently selected on the form (see DutyType). */
@Controller('duty-requirements')
export class DutyRequirementsController {
  constructor(private readonly dutyRequirementsService: DutyRequirementsService) {}

  @Get()
  get() {
    return this.dutyRequirementsService.get();
  }
}
