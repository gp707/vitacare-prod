import { ArrayMinSize, IsArray, IsIn, IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { City, Gender, Language, Qualification, Religion, Validation } from '@vitacare/shared-constants';

/**
 * Admin override — any subset of these fields (SPEC.md: "Edit caregiver
 * profile (admin override)").
 */
export class AdminEditCaregiverDto {
  @IsOptional()
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name?: string;

  @IsOptional()
  @IsIn(Object.values(Gender), { message: 'PROFILE_003' })
  gender?: Gender;

  @IsOptional()
  @IsInt({ message: 'PROFILE_004' })
  @Min(Validation.AGE_MIN, { message: 'PROFILE_004' })
  @Max(Validation.AGE_MAX, { message: 'PROFILE_004' })
  age?: number;

  @IsOptional()
  @IsArray({ message: 'PROFILE_005' })
  @ArrayMinSize(1, { message: 'PROFILE_005' })
  @IsIn(Object.values(Language), { each: true, message: 'PROFILE_006' })
  languages?: Language[];

  @IsOptional()
  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification?: Qualification;

  @IsOptional()
  @IsIn(Object.values(Religion), { message: 'PROFILE_010' })
  religion?: Religion;

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(City), { each: true, message: 'GEN_001' })
  preferred_cities?: City[];
}
