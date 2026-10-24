import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ListAffectedUsersQueryDto {
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

  /** Which errors count toward a person: 'open' (default) means someone whose
   *  errors were all handled drops off the list. */
  @IsOptional()
  @IsIn(['open', 'resolved', 'all'], { message: 'GEN_005' })
  status: 'open' | 'resolved' | 'all' = 'open';
}
