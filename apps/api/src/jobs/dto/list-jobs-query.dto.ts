import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';
import { City, JobStatus, Validation, WorkType } from '@vitacare/shared-constants';

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
  @IsIn(Object.values(WorkType), { message: 'GEN_005' })
  work_type?: WorkType;

  @IsOptional()
  @IsIn(Object.values(City), { message: 'GEN_005' })
  city?: City;
}
