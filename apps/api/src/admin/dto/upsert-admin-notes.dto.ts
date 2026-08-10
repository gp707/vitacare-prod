import { IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class UpsertAdminNotesDto {
  @IsOptional()
  @IsString()
  internal_notes?: string | null;

  @IsOptional()
  @IsNumber({}, { message: 'GEN_001' })
  @Min(0, { message: 'GEN_001' })
  rate_24hrs_live_in?: number | null;

  @IsOptional()
  @IsNumber({}, { message: 'GEN_001' })
  @Min(0, { message: 'GEN_001' })
  rate_12hrs_pg?: number | null;

  @IsOptional()
  @IsString()
  availability_remarks?: string | null;
}
