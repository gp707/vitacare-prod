import { IsString, MinLength } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ChangePasswordDto {
  @IsString({ message: 'GEN_001' })
  current_password!: string;

  @IsString({ message: 'GEN_001' })
  @MinLength(Validation.PASSWORD_MIN_LENGTH, { message: 'GEN_005' })
  new_password!: string;
}
