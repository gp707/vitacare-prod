import { Equals, IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

/** Individual (patient/family) registration is deliberately minimal —
 *  just phone and a login PIN. No gender/age/religion/qualification
 *  fields like caregiver registration; those don't apply to this account
 *  type. full_name is no longer collected on the registration form at
 *  all — AuthService.registerIndividual defaults it to the phone number
 *  when omitted, so every downstream consumer that displays a name still
 *  has something identifiable to show. */
export class RegisterIndividualDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  @IsOptional()
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  @MaxLength(Validation.NAME_MAX_LENGTH, { message: 'PROFILE_022' })
  full_name?: string;

  /** Same PROFILE_009 code caregiver registration uses — nursenow-app
   *  links out to an Individual-specific Terms & Conditions document
   *  (distinct from the Organisation one) before this can be checked. */
  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;

  /** Logs in with phone + this code from the very first session onward,
   *  same as a caregiver — EXCEPT when OTP mode is enabled for nursenow,
   *  see RegisterDto.code for the full explanation (identical pattern). */
  @IsOptional()
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code?: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  phone_verification_token?: string;
}
