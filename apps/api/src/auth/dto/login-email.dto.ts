import { IsEmail, MinLength } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class LoginEmailDto {
  @IsEmail({}, { message: 'GEN_001' })
  email!: string;

  @MinLength(Validation.PASSWORD_MIN_LENGTH, { message: 'GEN_001' })
  password!: string;
}
