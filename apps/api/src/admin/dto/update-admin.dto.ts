import { IsOptional, Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class UpdateAdminDto {
  @IsOptional()
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name?: string;

  @IsOptional()
  @Matches(Validation.PHONE_REGEX, { message: 'ADMIN_010' })
  phone?: string;
}
