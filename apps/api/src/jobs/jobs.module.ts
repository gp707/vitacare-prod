import { Module } from '@nestjs/common';
import { AdminJobsController } from './admin-jobs.controller';
import { CaregiverJobsController } from './caregiver-jobs.controller';
import { JobsService } from './jobs.service';
import { SalaryCyclesService } from './salary-cycles.service';

@Module({
  controllers: [AdminJobsController, CaregiverJobsController],
  providers: [JobsService, SalaryCyclesService],
  exports: [JobsService, SalaryCyclesService],
})
export class JobsModule {}
