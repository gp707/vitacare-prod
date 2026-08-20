import { IsOptional, Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

/**
 * Admin override for an individual (patient/family) account — an
 * individual_profiles row has no profile depth beyond the two block
 * levers, so the only editable field is the account's own name
 * (users.full_name).
 */
export class AdminEditIndividualDto {
  @IsOptional()
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name?: string;
}
