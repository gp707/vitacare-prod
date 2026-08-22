import { Equals, IsNotEmpty, Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

/** Individual (patient/family) registration is deliberately minimal —
 *  phone, name, and a login PIN. No gender/age/religion/qualification
 *  fields like caregiver registration; those don't apply to this account
 *  type. */
export class RegisterIndividualDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  @IsNotEmpty({ message: 'PROFILE_001' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name!: string;

  /** Same PROFILE_009 code caregiver registration uses — nursenow-app
   *  links out to an Individual-specific Terms & Conditions document
   *  (distinct from the Organisation one) before this can be checked. */
  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;

  /** Logs in with phone + this code from the very first session onward,
   *  same as a caregiver. */
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;
}
