import { Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class LoginCodeDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;
}
