import { Module } from '@nestjs/common';
import { UploadModule } from '../upload/upload.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from './admin-users.service';
import { AdminIndividualsController } from './admin-individuals.controller';
import { AdminIndividualsService } from './admin-individuals.service';

@Module({
  imports: [UploadModule],
  controllers: [AdminController, AdminUsersController, AdminIndividualsController],
  providers: [AdminService, AdminUsersService, AdminIndividualsService],
})
export class AdminModule {}
