import { IsBoolean, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { TypeOfNurse } from '@vitacare/shared-constants';

/** The "exclusive" org posting form — no care_receiver, no city/area/
 *  duty_type (inherited from the org's own registered location), and no
 *  frequency_of_care/salary_amount/start_date (admin-set on approval). */
export class CreateOrganisationRequirementDto {
  @IsIn(Object.values(TypeOfNurse), { message: 'GEN_001' })
  type_of_nurse!: string;

  @IsBoolean({ message: 'GEN_001' })
  accommodation_provided!: boolean;

  @IsBoolean({ message: 'GEN_001' })
  food_provided!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'GEN_001' })
  special_skills?: string;
}
