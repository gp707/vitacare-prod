import { IsNotEmpty, Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class UpdateNameDto {
  @IsNotEmpty({ message: 'PROFILE_001' })
  @Matches(Validation.NAME_REGEX, { message: 'PROFILE_020' })
  full_name!: string;
}
