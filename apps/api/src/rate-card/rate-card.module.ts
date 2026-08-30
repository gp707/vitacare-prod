import { Module } from '@nestjs/common';
import { RateCardController } from './rate-card.controller';
import { AdminRateCardController } from './admin-rate-card.controller';
import { RateCardService } from './rate-card.service';

@Module({
  controllers: [RateCardController, AdminRateCardController],
  providers: [RateCardService],
})
export class RateCardModule {}
