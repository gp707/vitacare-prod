import { Module } from '@nestjs/common';
import { DutyRequirementsController } from './duty-requirements.controller';
import { AdminDutyRequirementsController } from './admin-duty-requirements.controller';
import { DutyRequirementsService } from './duty-requirements.service';

@Module({
  controllers: [DutyRequirementsController, AdminDutyRequirementsController],
  providers: [DutyRequirementsService],
})
export class DutyRequirementsModule {}
