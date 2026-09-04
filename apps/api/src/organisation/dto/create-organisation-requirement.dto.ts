import {
  IsBoolean,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateIf,
} from 'class-validator';
import { Gender, TypeOfNurse } from '@vitacare/shared-constants';

/** The "exclusive" org posting form — no care_receiver, no city/area/
 *  duty_type (inherited from the org's own registered location), and no
 *  frequency_of_care/salary_amount/start_date (admin-set on approval). */
export class CreateOrganisationRequirementDto {
  @IsIn(Object.values(TypeOfNurse), { message: 'GEN_001' })
  type_of_nurse!: string;

  /** Required only when type_of_nurse is 'others' — mirrors
   *  care_receivers.medical_condition_other/toilet_assistance_other's
   *  conditional-reveal-and-require pattern. */
  @ValidateIf((o) => o.type_of_nurse === TypeOfNurse.OTHERS)
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(200, { message: 'GEN_001' })
  type_of_nurse_other?: string;

  @IsBoolean({ message: 'GEN_001' })
  accommodation_provided!: boolean;

  @IsBoolean({ message: 'GEN_001' })
  food_provided!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  special_skills?: string;

  /** Defaults to 1 (in the service, not here) when omitted. */
  @IsOptional()
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(49, { message: 'GEN_001' })
  number_of_vacancies?: number;

  /** Omitted/null = no preference. Only MALE/FEMALE are offered as a
   *  preference — same exclusion of Gender.OTHER as jobs.preferred_gender. */
  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: string;
}
