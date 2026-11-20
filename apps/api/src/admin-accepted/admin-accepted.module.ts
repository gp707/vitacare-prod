import { Module } from '@nestjs/common';
import { AdminAcceptedController } from './admin-accepted.controller';
import { AdminAcceptedService } from './admin-accepted.service';

@Module({
  controllers: [AdminAcceptedController],
  providers: [AdminAcceptedService],
})
export class AdminAcceptedModule {}
