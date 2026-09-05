import { IsIn, IsOptional } from 'class-validator';
import { CaregiverCloseReason } from '@vitacare/shared-constants';

/** Mirrors CompleteJobDto exactly — the caregiver's own reason for closing
 *  an accepted organisation requirement, optional at the DTO layer since
 *  an omitted/blank value defaults to NO_REASON in the service (see
 *  OrganisationRequirementsService.completeRequirement). */
export class CompleteRequirementDto {
  @IsOptional()
  @IsIn(Object.values(CaregiverCloseReason), { message: 'JOB_020' })
  close_reason?: string;
}
