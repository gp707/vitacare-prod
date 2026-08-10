import { ArrayMinSize, IsArray, IsIn } from 'class-validator';
import { WorkType } from '@vitacare/shared-constants';

export class AssignWorkTypesDto {
  @IsArray({ message: 'PROFILE_022' })
  @ArrayMinSize(1, { message: 'PROFILE_022' })
  @IsIn(Object.values(WorkType), { each: true, message: 'PROFILE_023' })
  work_types!: WorkType[];
}
