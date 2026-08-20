import { IsIn, IsNotEmpty, IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { City, OrganisationType, Validation } from '@vitacare/shared-constants';

/**
 * Admin override for an organisation (hospital/rehab/clinic) account — any
 * subset of these fields. full_name is the contact person's name
 * (users.full_name, kept in sync with organisation_profiles
 * .contact_person_name — see AdminOrganisationsService.editProfile).
 * city accepts the existing 7 cities plus 'others', same org-scoped list
 * as registration — not an extension of the shared City enum.
 */
export class AdminEditOrganisationDto {
  @IsOptional()
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name?: string;

  @IsOptional()
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(200, { message: 'GEN_001' })
  organisation_name?: string;

  @IsOptional()
  @IsIn(Object.values(OrganisationType), { message: 'GEN_001' })
  organisation_type?: string;

  @IsOptional()
  @IsIn([...Object.values(City), 'others'], { message: 'GEN_001' })
  city?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  area?: string;
}
