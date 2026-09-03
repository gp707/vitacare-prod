import { Controller, Get } from '@nestjs/common';
import { CaregiverMessagesService } from './caregiver-messages.service';

/** Public — no auth. caregiver-app's Messages bell fetches this fresh on
 *  every screen load and evaluates which messages currently apply
 *  client-side against its own already-fetched job/application data. */
@Controller('caregiver-messages')
export class CaregiverMessagesController {
  constructor(private readonly caregiverMessagesService: CaregiverMessagesService) {}

  @Get()
  get() {
    return this.caregiverMessagesService.get();
  }
}
