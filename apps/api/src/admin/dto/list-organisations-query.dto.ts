import { Transform, Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';
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

  @IsOptional()
  @IsIn(['created_at', 'org_number', 'organisation_name', 'organisation_type', 'city', 'full_name', 'phone'], {
    message: 'GEN_005',
  })
  sort: 'created_at' | 'org_number' | 'organisation_name' | 'organisation_type' | 'city' | 'full_name' | 'phone' =
    'created_at';

  @IsOptional()
  @IsIn(['asc', 'desc'], { message: 'GEN_005' })
  order: 'asc' | 'desc' = 'desc';

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

  /** Comma-separated account (user) ids: show only these accounts (e.g. the patients a caregiver is assigned to). */
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.split(',').map((v) => v.trim()).filter(Boolean) : value))
  @IsArray({ message: 'GEN_005' })
  @ArrayMaxSize(100, { message: 'GEN_005' })
  @IsUUID('all', { each: true, message: 'GEN_005' })
  user_ids?: string[];
}
