import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, Min } from 'class-validator';
import { City, JobStatus, OrganisationType } from '@vitacare/shared-constants';

/** organisation_requirements.status reuses JobStatus's exact 3 values. */
export class ListOrganisationRequirementsQueryDto {
  @IsOptional()
  @IsIn(Object.values(JobStatus), { message: 'GEN_001' })
  status?: string;

  /** Narrows to every requirement posted by one specific organisation
   *  account — used by admin-web's "View Jobs" redirect from a single
   *  Rehab/Hospitals row into the merged Jobs tab. */
  @IsOptional()
  @IsUUID(undefined, { message: 'GEN_005' })
  posted_by?: string;

  @IsOptional()
  @IsIn(Object.values(OrganisationType), { message: 'GEN_005' })
  organisation_type?: string;

  @IsOptional()
  @IsIn(Object.values(City), { message: 'GEN_005' })
  city?: string;

  /** Matches the organisation's name or the requirement's display id
   *  (ORG-JOB-<n>) / raw requirement_number. */
  @IsOptional()
  @IsString()
  search?: string;

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
