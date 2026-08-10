import { Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class UpdatePhoneDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;
}
