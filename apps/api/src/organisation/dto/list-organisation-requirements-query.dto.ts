import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Min } from 'class-validator';
import { JobStatus } from '@vitacare/shared-constants';

/** organisation_requirements.status reuses JobStatus's exact 3 values. */
export class ListOrganisationRequirementsQueryDto {
  @IsOptional()
  @IsIn(Object.values(JobStatus), { message: 'GEN_001' })
  status?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  page: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'GEN_005' })
  @Min(1, { message: 'GEN_005' })
  limit: number = 20;
}
