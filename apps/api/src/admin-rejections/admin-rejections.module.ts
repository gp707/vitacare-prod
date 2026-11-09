import { Module } from '@nestjs/common';
import { AdminRejectionsController } from './admin-rejections.controller';
import { AdminRejectionsService } from './admin-rejections.service';

@Module({
  controllers: [AdminRejectionsController],
  providers: [AdminRejectionsService],
})
export class AdminRejectionsModule {}
