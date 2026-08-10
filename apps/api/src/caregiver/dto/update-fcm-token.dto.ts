import { IsNotEmpty, IsString } from 'class-validator';

export class UpdateFcmTokenDto {
  @IsString({ message: 'PROFILE_021' })
  @IsNotEmpty({ message: 'PROFILE_021' })
  token!: string;
}
