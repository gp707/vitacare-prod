import { IsBoolean, IsIn, IsInt, IsISO8601, IsOptional, IsString, Max, MaxLength, Min, ValidateIf } from 'class-validator';
import { FrequencyOfCare, TypeOfNurse } from '@vitacare/shared-constants';

/** Admin's approve-via-edit body — same shape as create plus the three
 *  admin-set fields. start_date is required only when frequency_of_care is
 *  'daily' (ORG_001 otherwise); for 'monthly' it's ignored/nulled
 *  server-side regardless of what's sent. */
export class UpdateOrganisationRequirementDto {
  @IsIn(Object.values(TypeOfNurse), { message: 'GEN_001' })
  type_of_nurse!: string;

  @IsIn(Object.values(FrequencyOfCare), { message: 'GEN_001' })
  frequency_of_care!: string;

  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1000000, { message: 'GEN_001' })
  salary_amount!: number;

  @ValidateIf((o) => o.frequency_of_care === FrequencyOfCare.DAILY)
  @IsISO8601({ strict: true }, { message: 'ORG_001' })
  start_date?: string;

  @IsBoolean({ message: 'GEN_001' })
  accommodation_provided!: boolean;

  @IsBoolean({ message: 'GEN_001' })
  food_provided!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  special_skills?: string;
}
