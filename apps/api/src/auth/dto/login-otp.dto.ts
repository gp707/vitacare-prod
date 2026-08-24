import { IsIn, IsNotEmpty, IsString, Matches } from 'class-validator';
import { LoginApp, Validation } from '@vitacare/shared-constants';

export class LoginOtpDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  /** Which app is calling — same role-bucket disambiguation as
   *  LoginCodeDto.app (migration 045: phone unique per app bucket). */
  @IsIn(Object.values(LoginApp), { message: 'GEN_001' })
  app!: string;

  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'AUTH_010' })
  phone_verification_token!: string;
}
