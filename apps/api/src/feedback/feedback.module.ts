import { Module } from '@nestjs/common';
import { AdminFeedbackController, CaregiverFeedbackController, IndividualFeedbackController } from './feedback.controller';
import { FeedbackService } from './feedback.service';

@Module({
  controllers: [IndividualFeedbackController, CaregiverFeedbackController, AdminFeedbackController],
  providers: [FeedbackService],
})
export class FeedbackModule {}
