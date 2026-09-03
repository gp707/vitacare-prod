import { Module } from '@nestjs/common';
import { CaregiverMessagesController } from './caregiver-messages.controller';
import { AdminCaregiverMessagesController } from './admin-caregiver-messages.controller';
import { CaregiverMessagesService } from './caregiver-messages.service';

@Module({
  controllers: [CaregiverMessagesController, AdminCaregiverMessagesController],
  providers: [CaregiverMessagesService],
})
export class CaregiverMessagesModule {}
