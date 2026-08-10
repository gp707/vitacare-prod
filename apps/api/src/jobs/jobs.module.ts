import { Module } from '@nestjs/common';
import { AdminJobsController } from './admin-jobs.controller';
import { CaregiverJobsController } from './caregiver-jobs.controller';
import { JobsService } from './jobs.service';

@Module({
  controllers: [AdminJobsController, CaregiverJobsController],
  providers: [JobsService],
})
export class JobsModule {}
