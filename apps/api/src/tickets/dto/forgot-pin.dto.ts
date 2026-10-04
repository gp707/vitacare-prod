import { Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ForgotPinDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;
}
