import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ListRejectionsQueryDto {
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

  /** caregiver = caregiver declined/closed; poster = patient/organisation/admin rejected a caregiver. */
  @IsOptional()
  @IsIn(['caregiver', 'poster'], { message: 'GEN_005' })
  direction?: 'caregiver' | 'poster';

  @IsOptional()
  @IsString({ message: 'GEN_005' })
  @MaxLength(100, { message: 'GEN_005' })
  search?: string;
}
