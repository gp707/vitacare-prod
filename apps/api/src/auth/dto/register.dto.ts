import {
  ArrayMinSize,
  Equals,
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  Max,
  Min,
} from 'class-validator';
import { Gender, Language, Qualification, Religion, Validation } from '@vitacare/shared-constants';

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

  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification!: Qualification;

  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;

  /** Caregiver logs in with phone + this code from the very first session
   *  onward — EXCEPT when OTP mode is enabled for nursejobs, in which case
   *  `phone_verification_token` is sent instead and this is omitted. Which
   *  one is actually required is decided server-side in
   *  AuthService.resolveCredential (reads the live otp_auth_settings flag,
   *  never trusts the client) — hence both fields are optional here. */
  @IsOptional()
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code?: string;

  /** Proves phone ownership when OTP mode is enabled — issued by
   *  POST /auth/otp/verify (purpose: 'register'). */
  @IsOptional()
  @IsString({ message: 'GEN_001' })
  phone_verification_token?: string;
}
