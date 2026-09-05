import { IsIn, IsOptional } from 'class-validator';
import { CaregiverCloseReason } from '@vitacare/shared-constants';

/** The caregiver's own reason for closing an accepted job — optional at
 *  the DTO layer since an omitted/blank value defaults to NO_REASON in
 *  the service, not a validation error (see JobsService.completeJob). */
export class CompleteJobDto {
  @IsOptional()
  @IsIn(Object.values(CaregiverCloseReason), { message: 'JOB_020' })
  close_reason?: string;
}
