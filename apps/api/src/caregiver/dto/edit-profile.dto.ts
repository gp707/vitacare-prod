import { ArrayMinSize, IsArray, IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';
import { City, DutyType, Language, Qualification, Validation } from '@vitacare/shared-constants';

/**
 * Single self-edit endpoint for every caregiver-editable field. Any subset
 * — only what's provided gets written. full_name, gender, and religion are
 * intentionally NOT here — locked from self-edit once set at registration;
 * only admins can change them (PUT /admin/caregivers/{id}). Phone and the
 * login code live on their own endpoints (update-phone.dto.ts,
 * update-code.dto.ts) with different review-trigger semantics.
 *
 * preferred_cities, preferred_duty_types, min_salary_per_day, and
 * min_salary_per_month are job-search preferences (used to filter
 * GET /caregiver/jobs) rather than profile facts, but share the exact same
 * self-edit mechanics as everything else here — editable anytime, no
 * approval needed, never touches verification_status.
 */
export class EditProfileDto {
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
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(City), { each: true, message: 'GEN_001' })
  preferred_cities?: City[];

  // Empty array is valid (clears the preference) — unlike languages, this
  // is never required to be non-empty since "no preference" is a real,
  // meaningful state for job search filtering.
  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(DutyType), { each: true, message: 'GEN_001' })
  preferred_duty_types?: DutyType[];

  @IsOptional()
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1000000, { message: 'GEN_001' })
  min_salary_per_day?: number;

  @IsOptional()
  @IsInt({ message: 'GEN_001' })
  @Min(1, { message: 'GEN_001' })
  @Max(1000000, { message: 'GEN_001' })
  min_salary_per_month?: number;
}
