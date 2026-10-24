import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

/** Roles an Insights report can be narrowed to — admins are staff, never
 *  part of any of these reports. */
export const INSIGHT_ROLES = ['caregiver', 'individual', 'organisation'] as const;

export class PagedInsightsQueryDto {
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
}

export class ActiveUsersQueryDto extends PagedInsightsQueryDto {
  /** Look-back window — 24/48/168 are what admin-web offers, but any whole
   *  number of hours up to 30 days is accepted. */
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  @Max(720, { message: 'GEN_005' })
  hours: number = 24;

  @IsOptional()
  @IsIn(INSIGHT_ROLES, { message: 'GEN_005' })
  role?: (typeof INSIGHT_ROLES)[number];
}

export class InactiveSinceRegistrationQueryDto extends PagedInsightsQueryDto {
  /** Only accounts registered at least this long ago — a person who
   *  registered ten minutes ago hasn't "failed to come back" yet. */
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  @Max(8760, { message: 'GEN_005' })
  min_age_hours: number = 24;

  @IsOptional()
  @IsIn(INSIGHT_ROLES, { message: 'GEN_005' })
  role?: (typeof INSIGHT_ROLES)[number];
}

export class TopActionsQueryDto {
  @IsOptional()
  @IsIn(['tap', 'screen'], { message: 'GEN_005' })
  kind: 'tap' | 'screen' = 'tap';

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  @Max(90, { message: 'GEN_005' })
  days: number = 7;

  @IsOptional()
  @Matches(/^[a-z0-9_]{1,40}$/, { message: 'GEN_005' })
  flow?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  @Max(100, { message: 'GEN_005' })
  limit: number = 25;
}
