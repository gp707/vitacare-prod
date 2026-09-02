import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';
import { City, DutyType, Gender, JobStatus, Language, UserRole, Validation } from '@vitacare/shared-constants';

export class ListJobsQueryDto {
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
  @IsIn(Object.values(JobStatus), { message: 'GEN_005' })
  status?: JobStatus;

  @IsOptional()
  @IsIn(Object.values(City), { message: 'GEN_005' })
  city?: City;

  @IsOptional()
  @IsUUID(undefined, { message: 'GEN_005' })
  posted_by?: string;

  // Filters to jobs posted by any user of this role — e.g. 'individual' to
  // see just NurseNow patient/family postings vs admin's own ('admin' or
  // 'super_admin'). One level up from posted_by (a specific user).
  @IsOptional()
  @IsIn(Object.values(UserRole), { message: 'GEN_005' })
  posted_by_role?: UserRole;

  // Patient's gender, on care_receivers — not to be confused with a job's
  // preferred_gender (a caregiver preference).
  @IsOptional()
  @IsIn(Object.values(Gender), { message: 'GEN_005' })
  gender?: Gender;

  @IsOptional()
  @IsIn(Object.values(DutyType), { message: 'GEN_005' })
  duty_type?: DutyType;

  // Matches jobs whose languages array includes this one value.
  @IsOptional()
  @IsIn(Object.values(Language), { message: 'GEN_005' })
  language?: Language;

  // Matches against the job's own display id (ADMIN-JOB-<n>/PAT-JOB-<n>) or
  // the posting individual's own display id (PAT-<n>) — e.g. "PAT-501"
  // finds every job that patient/family account has posted, not just one
  // job by its own id.
  @IsOptional()
  @IsString()
  search?: string;

  // Finds jobs whose posted_at is more than this many days in the past —
  // e.g. jobs that have fallen out of their caregiver-facing apply-by
  // urgency window (Validation.APPLY_BY_WINDOW_DAYS) and may need manual
  // admin attention. Orthogonal to `status` (same as every other filter
  // here) — combine with status=active to find ones still open.
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  posted_more_than_days_ago?: number;
}
