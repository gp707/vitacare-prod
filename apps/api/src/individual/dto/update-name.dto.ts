import { IsNotEmpty, Matches, MaxLength } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class UpdateNameDto {
  @IsNotEmpty({ message: 'PROFILE_001' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  @MaxLength(Validation.NAME_MAX_LENGTH, { message: 'PROFILE_022' })
  full_name!: string;
}
