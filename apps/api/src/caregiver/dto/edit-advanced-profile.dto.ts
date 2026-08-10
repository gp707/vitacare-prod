import {
  IsArray,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { City, Qualification, Validation } from '@vitacare/shared-constants';

/**
 * Caregiver self-edit of the advanced-details fields, any time after the
 * initial submission (unlike SubmitAdvancedDetailsDto, which is a one-time/
 * resubmission-only whole-object replace gated to call_verified/rejected).
 * Any subset of these fields — only what's provided gets written. None of
 * these trigger a re-review (unlike phone/Aadhaar); they just flag
 * has_pending_edits for admin visibility.
 *
 * Religion is deliberately NOT here — once set (at initial submission or a
 * rejected resubmission via SubmitAdvancedDetailsDto), it's locked from
 * further self-edit; only admins can change it from that point on.
 */
export class EditAdvancedProfileDto {
  @IsOptional()
  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification?: Qualification;

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
