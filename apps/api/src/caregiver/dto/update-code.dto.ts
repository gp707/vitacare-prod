import { Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class UpdateCodeDto {
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;
}
