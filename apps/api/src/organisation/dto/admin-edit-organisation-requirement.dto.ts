import { IsBoolean, IsIn, IsInt, IsNotEmpty, IsOptional, IsString, Max, MaxLength, Min, ValidateIf } from 'class-validator';
import { Gender, RequirementDuration, TypeOfNurse, Validation } from '@vitacare/shared-constants';

/** Admin's edit body (PATCH /admin/organisation-requirements/:id) — every
 *  field the org itself can set via UpdateMyOrganisationRequirementDto,
 *  mirrored here but all optional so a bare/empty body still works as a
 *  pure approve (see OrganisationRequirementsService.adminEditRequirement,
 *  which merges each provided field over the existing row). Reverses the
 *  original "admin owns no fields at all" design on explicit request —
 *  admin can now edit anything the org itself could. */
export class AdminEditOrganisationRequirementDto {
  @IsOptional()
  @IsIn(Object.values(TypeOfNurse), { message: 'GEN_001' })
  type_of_nurse?: string;

  @ValidateIf((o) => o.type_of_nurse === TypeOfNurse.OTHERS)
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(200, { message: 'GEN_001' })
  type_of_nurse_other?: string;

  @IsOptional()
  @IsBoolean({ message: 'GEN_001' })
  accommodation_provided?: boolean;

  @IsOptional()
  @IsBoolean({ message: 'GEN_001' })
  food_provided?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(Validation.SPECIAL_SKILLS_MAX_LENGTH, { message: 'GEN_001' })
  special_skills?: string;

  @IsOptional()
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(49, { message: 'GEN_001' })
  number_of_vacancies?: number;

  @IsOptional()
  @IsIn([Gender.MALE, Gender.FEMALE], { message: 'GEN_001' })
  preferred_gender?: string;

  @IsOptional()
  @IsIn(Object.values(RequirementDuration), { message: 'GEN_001' })
  duration_type?: string;
}
