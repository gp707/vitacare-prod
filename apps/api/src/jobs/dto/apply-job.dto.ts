import { IsIn } from 'class-validator';
import { JobApplicationStatus } from '@vitacare/shared-constants';

export class ApplyJobDto {
  // Caregiver self-action — only these two values are ever valid here;
  // 'accepted' is admin-only (see DecideApplicationDto).
  @IsIn([JobApplicationStatus.APPLIED, JobApplicationStatus.REJECTED], { message: 'JOB_004' })
  status!: typeof JobApplicationStatus.APPLIED | typeof JobApplicationStatus.REJECTED;
}
