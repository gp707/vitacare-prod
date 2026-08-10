import { IsIn } from 'class-validator';
import { UserRole } from '@vitacare/shared-constants';

export class UpdateAdminRoleDto {
  @IsIn([UserRole.ADMIN, UserRole.SUPER_ADMIN], { message: 'GEN_001' })
  role!: UserRole;
}
