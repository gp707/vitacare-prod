import { IsInt, Matches, Max, Min } from 'class-validator';

/** What the patient/family and the accepted caregiver agreed, confirmed right
 *  after accepting. The salary unit (per day / per month) is not sent: it
 *  follows the job's own frequency_of_care. */
export class SetAgreementDto {
  @IsInt()
  @Min(1)
  @Max(1_000_000)
  agreed_salary!: number;

  /** YYYY-MM-DD; today or later (JOB_023), checked in the service. */
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  agreed_start_date!: string;
}
