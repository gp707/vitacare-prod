import { ArrayMinSize, IsArray, IsIn } from 'class-validator';
import { ServiceMode } from '@vitacare/shared-constants';

export class AssignServiceModesDto {
  @IsArray({ message: 'PROFILE_012' })
  @ArrayMinSize(1, { message: 'PROFILE_012' })
  @IsIn(Object.values(ServiceMode), { each: true, message: 'PROFILE_013' })
  service_modes!: ServiceMode[];
}
