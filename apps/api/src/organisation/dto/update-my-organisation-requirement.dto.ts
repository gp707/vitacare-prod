import { IsBoolean, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min, ValidateIf } from 'class-validator';
import { Gender, TypeOfNurse } from '@vitacare/shared-constants';

/** The org's own self-edit body (PATCH /organisation/requirements/:id) —
 *  exactly the org-owned fields set at creation (see
 *  CreateOrganisationRequirementDto), never frequency_of_care/salary_amount/
 *  schedule_type, which stay admin-only (see UpdateOrganisationRequirementDto).
 *  Mirrors UpdateIndividualRequirementDto's "edit any field the poster
 *  controls, none of the admin-set ones" split. */
export class UpdateMyOrganisationRequirementDto {
  @IsIn(Object.values(TypeOfNurse), { message: 'GEN_001' })
  type_of_nurse!: string;

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

  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(49, { message: 'GEN_001' })
  number_of_vacancies!: number;

  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: string;
}
