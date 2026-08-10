import { IsIn, IsNotEmpty, IsString, ValidateIf } from 'class-validator';
import { JobResponse } from '@vitacare/shared-constants';

export class RespondJobDto {
  @IsIn(Object.values(JobResponse), { message: 'JOB_004' })
  response!: JobResponse;

  // Required only when asking for more details (SPEC.md 6.6) — validation
  // is skipped entirely (not just "optional") for every other response
  // value, via ValidateIf's predicate. Every decorator here shares the
  // same JOB_003 code deliberately — validationExceptionFactory picks
  // whichever constraint happens to fail first, so mixing codes on one
  // field is a real ordering hazard, not just style.
  @ValidateIf((o: RespondJobDto) => o.response === JobResponse.MORE_DETAILS)
  @IsNotEmpty({ message: 'JOB_003' })
  @IsString({ message: 'JOB_003' })
  message?: string;
}
