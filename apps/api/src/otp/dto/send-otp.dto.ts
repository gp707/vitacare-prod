import { IsIn, Matches } from 'class-validator';
import { LoginApp, OtpPurpose, Validation } from '@vitacare/shared-constants';

export class SendOtpDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  @IsIn(Object.values(LoginApp), { message: 'GEN_001' })
  app!: string;

  @IsIn(Object.values(OtpPurpose), { message: 'GEN_001' })
  purpose!: string;
}
