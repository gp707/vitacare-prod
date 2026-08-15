import { IsArray, IsIn, IsOptional } from 'class-validator';
import { City, Qualification } from '@vitacare/shared-constants';

/**
 * Caregiver self-edit of the advanced-details fields, any time after the
 * initial submission (unlike SubmitAdvancedDetailsDto, which is a one-time/
 * resubmission-only whole-object replace gated to call_verified/rejected).
 * Any subset of these fields — only what's provided gets written. None of
 * these trigger a re-review (unlike phone/Aadhaar); they just flag
 * has_pending_edits for admin visibility.
 *
 * Religion is deliberately NOT here — set once at registration, it's
 * locked from further self-edit; only admins can change it from that point
 * on. father_name, father_phone, current_address, and notes have been
 * removed from the product entirely.
 */
export class EditAdvancedProfileDto {
  @IsOptional()
  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification?: Qualification;

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(City), { each: true, message: 'GEN_001' })
  preferred_cities?: City[];
}
