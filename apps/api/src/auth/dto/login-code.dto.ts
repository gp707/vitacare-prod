import { IsIn, Matches } from 'class-validator';
import { LoginApp, Validation } from '@vitacare/shared-constants';

export class LoginCodeDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;

  /** Which app is calling — phone is unique per app bucket (migration 045),
   *  not globally, so this tells the lookup which bucket to search:
   *  'nursejobs' -> role=caregiver only, 'nursenow' -> role IN (individual,
   *  organisation). */
  @IsIn(Object.values(LoginApp), { message: 'GEN_001' })
  app!: string;
}
