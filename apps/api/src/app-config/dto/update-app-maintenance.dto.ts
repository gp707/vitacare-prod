import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';

export class UpdateAppMaintenanceDto {
  @IsBoolean({ message: 'GEN_001' })
  enabled!: boolean;

  @IsOptional()
  @IsString({ message: 'GEN_001' })
  @MaxLength(500, { message: 'GEN_001' })
  message?: string;
}
