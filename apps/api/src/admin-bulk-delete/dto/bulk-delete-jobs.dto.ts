import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, Equals, IsIn, IsUUID, ValidateNested } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

export class BulkDeleteItemDto {
  @IsUUID(undefined, { message: 'GEN_001' })
  id!: string;

  // Which table this id belongs to — the merged admin-web Jobs screen
  // shows rows from two entirely separate tables (jobs vs
  // organisation_requirements, see CLAUDE.md's "NurseNow" section), so a
  // single bulk-delete call needs to know which delete path each id takes.
  @IsIn(['job', 'organisation_requirement'], { message: 'GEN_001' })
  type!: 'job' | 'organisation_requirement';
}

export class BulkDeleteJobsDto {
  @ValidateNested({ each: true })
  @Type(() => BulkDeleteItemDto)
  @ArrayMinSize(1, { message: 'GEN_001' })
  @ArrayMaxSize(Validation.BULK_DELETE_MAX_ITEMS, { message: 'JOB_018' })
  items!: BulkDeleteItemDto[];

  // Defense in depth alongside admin-web's own "type DELETE to confirm"
  // dialog gate — a malformed/scripted request without the literal
  // confirmation string never reaches the service layer.
  @Equals('DELETE', { message: 'GEN_001' })
  confirm!: string;
}
