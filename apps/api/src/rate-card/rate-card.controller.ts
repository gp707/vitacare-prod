import { Controller, Get } from '@nestjs/common';
import { RateCardService } from './rate-card.service';

/** Public — no auth. Caregiver-app and nursenow-app (Individual only) fetch
 *  this to render behind a persistent app-bar icon on every screen. */
@Controller('rate-card')
export class RateCardController {
  constructor(private readonly rateCardService: RateCardService) {}

  @Get()
  get() {
    return this.rateCardService.get();
  }
}
