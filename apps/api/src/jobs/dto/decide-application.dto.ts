import { IsIn } from 'class-validator';
import { JobApplicationStatus } from '@vitacare/shared-constants';

export class DecideApplicationDto {
  // Admin-only action — 'applied' is never a valid target here.
  @IsIn([JobApplicationStatus.ACCEPTED, JobApplicationStatus.REJECTED], { message: 'JOB_004' })
  status!: typeof JobApplicationStatus.ACCEPTED | typeof JobApplicationStatus.REJECTED;
}
