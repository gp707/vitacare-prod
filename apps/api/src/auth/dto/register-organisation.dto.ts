import { Equals, IsIn, IsNotEmpty, IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { City, OrganisationType, Validation } from '@vitacare/shared-constants';

/** Organisation (hospital/rehab/clinic) registration — phone/PIN like
 *  every other NurseNow account type, plus the identity/location fields an
 *  org needs since it has no separate per-requirement city/area (every
 *  requirement inherits city/area from here). city accepts the existing 7
 *  cities plus 'others' — a separate org-scoped list, not an extension of
 *  the shared City enum used elsewhere for filtering. */
export class RegisterOrganisationDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  /** Logs in with phone + this code from the very first session onward —
   *  EXCEPT when OTP mode is enabled for nursenow, see RegisterDto.code for
   *  the full explanation (identical pattern). */
  @IsOptional()
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code?: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  phone_verification_token?: string;

  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(200, { message: 'GEN_001' })
  organisation_name!: string;

  @IsNotEmpty({ message: 'PROFILE_001' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  contact_person_name!: string;

  @IsIn(Object.values(OrganisationType), { message: 'GEN_001' })
  organisation_type!: string;

  @IsIn([...Object.values(City), 'others'], { message: 'GEN_001' })
  city!: string;

  @IsString()
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  area!: string;

  /** Same PROFILE_009 code caregiver/individual registration uses —
   *  nursenow-app links out to an Organisation-specific Terms &
   *  Conditions document (distinct from the Individual one) before this
   *  can be checked. */
  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;
}
