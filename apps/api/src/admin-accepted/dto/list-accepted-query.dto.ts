import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class ListAcceptedQueryDto {
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

  /** Current status of the accepted application: accepted = still on it, completed = closed duty,
   *  rejected = accepted then let go / declined, applied = re-applied afterwards. */
  @IsOptional()
  @IsIn(['accepted', 'completed', 'rejected', 'applied'], { message: 'GEN_005' })
  status?: 'accepted' | 'completed' | 'rejected' | 'applied';

  @IsOptional()
  @IsString({ message: 'GEN_005' })
  @MaxLength(100, { message: 'GEN_005' })
  search?: string;
}
