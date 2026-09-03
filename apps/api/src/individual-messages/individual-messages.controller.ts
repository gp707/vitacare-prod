import { Controller, Get } from '@nestjs/common';
import { IndividualMessagesService } from './individual-messages.service';

/** Public — no auth. nursenow-app's Individual Messages tab fetches this
 *  fresh on every screen open and evaluates which messages currently
 *  apply client-side against its own already-fetched requirement data. */
@Controller('individual-messages')
export class IndividualMessagesController {
  constructor(private readonly individualMessagesService: IndividualMessagesService) {}

  @Get()
  get() {
    return this.individualMessagesService.get();
  }
}
