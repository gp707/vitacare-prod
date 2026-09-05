import { Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { AuditAction, Validation } from '@vitacare/shared-constants';

export class ListAuditLogsQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  page: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  @Max(Validation.PAGINATION_MAX_LIMIT, { message: 'GEN_005' })
  limit: number = Validation.PAGINATION_DEFAULT_LIMIT;

  @IsOptional()
  @IsIn(['created_at'], { message: 'GEN_005' })
  sort = 'created_at' as const;

  @IsOptional()
  @IsIn(['asc', 'desc'], { message: 'GEN_005' })
  order: 'asc' | 'desc' = 'desc';

  @IsOptional()
  @IsUUID(undefined, { message: 'GEN_005' })
  user_id?: string;

  @IsOptional()
  @IsUUID(undefined, { message: 'GEN_005' })
  target_user_id?: string;

  @IsOptional()
  @IsIn(Object.values(AuditAction), { message: 'GEN_005' })
  action?: AuditAction;

  @IsOptional()
  @IsDateString({}, { message: 'GEN_005' })
  from_date?: string;

  @IsOptional()
  @IsDateString({}, { message: 'GEN_005' })
  to_date?: string;

  // Free-text — matches the actor's/target's name or phone, the target's
  // display id (NUR-/PAT-/ORG-<n>), the entry's entity_type, or the
  // affected job/requirement's own display id (ADMIN-JOB-/PAT-JOB-/
  // ORG-JOB-<n>). Same ILIKE-search convention as every other admin-web
  // list screen's filter panel.
  @IsOptional()
  @IsString({ message: 'GEN_005' })
  @MaxLength(200, { message: 'GEN_005' })
  search?: string;
}
