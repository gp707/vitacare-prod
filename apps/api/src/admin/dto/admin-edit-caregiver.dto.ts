import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { City, Gender, Language, Qualification, Religion, Validation } from '@vitacare/shared-constants';

/**
 * Admin override — any subset of these fields (SPEC.md: "Edit caregiver
 * profile (admin override)"). Does NOT include service_modes, work_types,
 * or salary — those are admin-assigned via their own dedicated endpoints
 * (CLAUDE.md: read-only for caregivers, assigned through a single tracked
 * channel), not this generic profile edit.
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
  @IsNotEmpty({ message: 'PROFILE_011' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  father_name?: string;

  @IsOptional()
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  father_phone?: string;

  @IsOptional()
  @IsNotEmpty({ message: 'PROFILE_014' })
  @MaxLength(Validation.ADDRESS_MAX_LENGTH, { message: 'PROFILE_015' })
  current_address?: string;

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(City), { each: true, message: 'GEN_001' })
  preferred_cities?: City[];

  @IsOptional()
  @IsString()
  @MaxLength(Validation.NOTES_MAX_LENGTH, { message: 'GEN_001' })
  notes?: string | null;
}
