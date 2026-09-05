import { IsIn } from 'class-validator';
import { LoginApp } from '@vitacare/shared-constants';

export class MaintenanceCheckQueryDto {
  @IsIn(Object.values(LoginApp), { message: 'GEN_001' })
  app!: LoginApp;
}
