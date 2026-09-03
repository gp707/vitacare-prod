import { Module } from '@nestjs/common';
import { IndividualMessagesController } from './individual-messages.controller';
import { AdminIndividualMessagesController } from './admin-individual-messages.controller';
import { IndividualMessagesService } from './individual-messages.service';

@Module({
  controllers: [IndividualMessagesController, AdminIndividualMessagesController],
  providers: [IndividualMessagesService],
})
export class IndividualMessagesModule {}
