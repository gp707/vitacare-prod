import { IsIn, IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { FrequencyOfCare } from '@vitacare/shared-constants';

/** What the patient/family and the accepted caregiver agreed, confirmed right
 *  after accepting. [agreed_salary_unit] ('daily' = per day, 'monthly' = per
 *  month) is the patient's choice; when omitted (an older app build) it follows
 *  the job's own frequency_of_care. */
export class SetAgreementDto {
  @IsInt()
  @Min(1)
  @Max(1_000_000)
  agreed_salary!: number;

  @IsOptional()
  @IsIn([FrequencyOfCare.DAILY, FrequencyOfCare.MONTHLY])
  agreed_salary_unit?: typeof FrequencyOfCare.DAILY | typeof FrequencyOfCare.MONTHLY;

  /** YYYY-MM-DD; today or later (JOB_023), checked in the service. */
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  agreed_start_date!: string;
}
