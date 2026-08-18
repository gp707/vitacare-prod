import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { City, DutyType, Gender, JobStatus, Language, Validation } from '@vitacare/shared-constants';

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
}
