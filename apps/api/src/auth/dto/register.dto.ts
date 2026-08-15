import { ArrayMinSize, Equals, IsArray, IsIn, IsInt, IsNotEmpty, IsOptional, Matches, Max, Min } from 'class-validator';
import { City, Gender, Language, Qualification, Religion, Validation } from '@vitacare/shared-constants';

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

  @IsIn(Object.values(Religion), { message: 'PROFILE_010' })
  religion!: Religion;

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(City), { each: true, message: 'GEN_001' })
  preferred_cities?: City[];

  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification!: Qualification;

  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;

  /** Caregiver logs in with phone + this code from the very first session
   * onward. */
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;
}
