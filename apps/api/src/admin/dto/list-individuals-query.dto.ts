import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ListIndividualsQueryDto {
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
  @IsIn(['created_at', 'patient_number', 'full_name', 'phone'], { message: 'GEN_005' })
  sort: 'created_at' | 'patient_number' | 'full_name' | 'phone' = 'created_at';

  @IsOptional()
  @IsIn(['asc', 'desc'], { message: 'GEN_005' })
  order: 'asc' | 'desc' = 'desc';

  /** Matches full_name, phone, or the display id (PAT-<n>). */
  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsIn(['active', 'job_posting_blocked', 'blocked'], { message: 'GEN_005' })
  block_status?: 'active' | 'job_posting_blocked' | 'blocked';
}
