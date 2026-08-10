import { IsNotEmpty, IsString } from 'class-validator';

export class RefreshTokenDto {
  @IsString({ message: 'GEN_001' })
  @IsNotEmpty({ message: 'GEN_001' })
  refresh_token!: string;
}
