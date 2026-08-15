import { Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { Qualification, Validation, VerificationStatus } from '@vitacare/shared-constants';

export class ListCaregiversQueryDto {
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
  @IsIn(['created_at', 'full_name', 'age'], { message: 'GEN_005' })
  sort: 'created_at' | 'full_name' | 'age' = 'created_at';

  @IsOptional()
  @IsIn(['asc', 'desc'], { message: 'GEN_005' })
  order: 'asc' | 'desc' = 'desc';

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsIn(Object.values(VerificationStatus), { message: 'GEN_005' })
  status?: VerificationStatus;

  @IsOptional()
  @IsIn(Object.values(Qualification), { message: 'GEN_005' })
  qualification?: Qualification;

  /** Comma-separated list of languages (matches any). */
  @IsOptional()
  @IsString()
  language?: string;

  @IsOptional()
  @IsDateString({}, { message: 'GEN_005' })
  from_date?: string;

  @IsOptional()
  @IsDateString({}, { message: 'GEN_005' })
  to_date?: string;
}
