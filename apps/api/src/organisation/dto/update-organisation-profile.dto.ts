import { IsIn, IsNotEmpty, IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { City, OrganisationType, Validation } from '@vitacare/shared-constants';

/**
 * Org self-service edit of every org-owned profile field — mirrors
 * AdminEditOrganisationDto exactly (same validation), just called by the
 * organisation itself via PATCH /organisation/profile instead of admin's
 * PUT /admin/organisations/:id. full_name is the contact person's name
 * (users.full_name, kept in sync with organisation_profiles
 * .contact_person_name — see OrganisationService.updateProfile). Phone and
 * the login code stay on their own dedicated endpoints
 * (PATCH /organisation/profile/phone, /code), unaffected by this one.
 */
export class UpdateOrganisationProfileDto {
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
