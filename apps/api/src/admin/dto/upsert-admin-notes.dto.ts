import { IsOptional, IsString } from 'class-validator';

export class UpsertAdminNotesDto {
  @IsOptional()
  @IsString()
  internal_notes?: string | null;

  @IsOptional()
  @IsString()
  availability_remarks?: string | null;
}
