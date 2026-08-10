import { ArrayMinSize, IsArray, IsIn, IsInt, IsNotEmpty, Matches, Max, Min } from 'class-validator';
import { Gender, Language, Validation } from '@vitacare/shared-constants';

export class RegisterDto {
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  phone!: string;

  @IsNotEmpty({ message: 'PROFILE_001' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name!: string;

  @IsIn(Object.values(Gender), { message: 'PROFILE_003' })
  gender!: Gender;

  @IsInt({ message: 'PROFILE_004' })
  @Min(Validation.AGE_MIN, { message: 'PROFILE_004' })
  @Max(Validation.AGE_MAX, { message: 'PROFILE_004' })
  age!: number;

  @IsArray({ message: 'PROFILE_005' })
  @ArrayMinSize(1, { message: 'PROFILE_005' })
  @IsIn(Object.values(Language), { each: true, message: 'PROFILE_006' })
  languages!: Language[];

  /** Set at registration (not Stage 3/advanced-details) — caregiver logs in
   * with phone + this code from the very first session onward. */
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;
}
