import { IsBoolean, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min, ValidateIf } from 'class-validator';
import { Gender, RequirementDuration, TypeOfNurse } from '@vitacare/shared-constants';

/** The org's own self-edit body (PATCH /organisation/requirements/:id) —
 *  every field the org itself controls (see CreateOrganisationRequirementDto).
 *  There is no admin-set counterpart to any of these — admin's own approval
 *  is a pure approve/reject click with no fields at all (see
 *  OrganisationRequirementsService.approveRequirement). */
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

  @IsIn(Object.values(RequirementDuration), { message: 'GEN_001' })
  duration_type!: string;
}
