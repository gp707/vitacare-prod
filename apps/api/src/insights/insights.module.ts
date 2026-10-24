import { Module } from '@nestjs/common';
import { AdminInsightsController } from './admin-insights.controller';
import { EventsController } from './events.controller';
import { InsightsService } from './insights.service';
import { OptionalJwtAuthGuard } from '../common/guards/optional-jwt-auth.guard';

@Module({
  controllers: [AdminInsightsController, EventsController],
  providers: [InsightsService, OptionalJwtAuthGuard],
})
export class InsightsModule {}
