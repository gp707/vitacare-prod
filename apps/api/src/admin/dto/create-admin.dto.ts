import { IsEmail, IsIn, IsOptional, Matches, MinLength } from 'class-validator';
import { UserRole, Validation } from '@vitacare/shared-constants';

export class CreateAdminDto {
  @IsEmail({}, { message: 'GEN_001' })
  email!: string;

  @Matches(Validation.PHONE_REGEX, { message: 'ADMIN_010' })
  phone!: string;

  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name!: string;

  @MinLength(Validation.PASSWORD_MIN_LENGTH, { message: 'GEN_001' })
  password!: string;

  /** Defaults to `admin`. A super admin is only ever made by promoting. */
  @IsOptional()
  @IsIn([UserRole.ADMIN, UserRole.READ_ONLY_ADMIN], { message: 'GEN_001' })
  role?: UserRole;
}
