import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min, Max } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ListErrorLogsQueryDto {
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

  /** Defaults to 'all' so existing callers see exactly what they always did;
   *  admin-web asks for 'open' to show what still needs attention. */
  @IsOptional()
  @IsIn(['open', 'resolved', 'all'], { message: 'GEN_005' })
  status: 'open' | 'resolved' | 'all' = 'all';

  /** Only errors hit by this one person. */
  @IsOptional()
  @IsUUID('4', { message: 'GEN_005' })
  user_id?: string;

  /** Case-insensitive match on the request path or the error message. */
  @IsOptional()
  @IsString({ message: 'GEN_005' })
  @MaxLength(100, { message: 'GEN_005' })
  search?: string;
}
