import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { City, OrganisationType, Validation } from '@vitacare/shared-constants';

export class ListOrganisationsQueryDto {
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

  /** Matches organisation_name, contact full_name, phone, or the display id
   *  (ORG-<n>). */
  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsIn(['active', 'job_posting_blocked', 'blocked'], { message: 'GEN_005' })
  block_status?: 'active' | 'job_posting_blocked' | 'blocked';

  @IsOptional()
  @IsIn(Object.values(OrganisationType), { message: 'GEN_005' })
  organisation_type?: string;

  /** Same org-scoped list as registration — the existing 7 cities plus
   *  'others', not an extension of the shared City enum. */
  @IsOptional()
  @IsIn([...Object.values(City), 'others'], { message: 'GEN_005' })
  city?: string;
}
