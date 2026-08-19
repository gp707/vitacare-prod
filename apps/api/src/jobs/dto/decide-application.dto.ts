import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { JobApplicationStatus } from '@vitacare/shared-constants';

export class DecideApplicationDto {
  // Admin-only action — 'applied' is never a valid target here.
  @IsIn([JobApplicationStatus.ACCEPTED, JobApplicationStatus.REJECTED], { message: 'JOB_004' })
  status!: typeof JobApplicationStatus.ACCEPTED | typeof JobApplicationStatus.REJECTED;

  // Optional here — a NurseNow individual rejecting an applicant is
  // required to supply one, but that's enforced in IndividualService, not
  // this shared DTO, since admin's own reject flow doesn't require it.
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  reason?: string;
}
