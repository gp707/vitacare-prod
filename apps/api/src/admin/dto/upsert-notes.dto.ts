import { IsOptional, IsString } from 'class-validator';

/** Shared by the job and individual admin-notes endpoints — a single
 *  free-text notes field, unlike caregiver's UpsertAdminNotesDto which
 *  also carries availability_remarks (a caregiver-specific concept). */
export class UpsertNotesDto {
  @IsOptional()
  @IsString()
  notes?: string | null;
}
