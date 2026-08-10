import { Module } from '@nestjs/common';
import { UploadModule } from '../upload/upload.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from './admin-users.service';

@Module({
  imports: [UploadModule],
  controllers: [AdminController, AdminUsersController],
  providers: [AdminService, AdminUsersService],
})
export class AdminModule {}
