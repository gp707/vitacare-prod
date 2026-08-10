import { IsEmail, Matches, MinLength } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class CreateAdminDto {
  @IsEmail({}, { message: 'GEN_001' })
  email!: string;

  @Matches(Validation.PHONE_REGEX, { message: 'ADMIN_010' })
  phone!: string;

  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name!: string;

  @MinLength(Validation.PASSWORD_MIN_LENGTH, { message: 'GEN_001' })
  password!: string;
}
