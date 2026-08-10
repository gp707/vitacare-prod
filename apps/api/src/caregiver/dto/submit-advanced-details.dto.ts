import {
  Equals,
  IsArray,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { City, Qualification, Religion, Validation } from '@vitacare/shared-constants';

export class SubmitAdvancedDetailsDto {
  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification!: Qualification;

  @IsIn(Object.values(Religion), { message: 'PROFILE_010' })
  religion!: Religion;

  @IsOptional()
  @IsNotEmpty({ message: 'PROFILE_011' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  father_name?: string;

  @IsOptional()
  @Matches(Validation.PHONE_REGEX, { message: 'PROFILE_007' })
  father_phone?: string;

  @IsOptional()
  @IsNotEmpty({ message: 'PROFILE_014' })
  @MaxLength(Validation.ADDRESS_MAX_LENGTH, { message: 'PROFILE_015' })
  current_address?: string;

  @IsOptional()
  @IsArray({ message: 'GEN_001' })
  @IsIn(Object.values(City), { each: true, message: 'GEN_001' })
  preferred_cities?: City[];

  @IsOptional()
  @IsString()
  @MaxLength(Validation.NOTES_MAX_LENGTH, { message: 'GEN_001' })
  notes?: string | null;

  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;
}
