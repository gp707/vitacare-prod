import { IsOptional, IsString, Matches, MaxLength } from 'class-validator';

export class UpdateAppVersionDto {
  @Matches(/^\d+\.\d+\.\d+$/, { message: 'GEN_001' })
  min_version!: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  store_url?: string;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  update_message?: string;
}
