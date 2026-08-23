import { Module } from '@nestjs/common';
import { UploadModule } from '../upload/upload.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from './admin-users.service';
import { AdminIndividualsController } from './admin-individuals.controller';
import { AdminIndividualsService } from './admin-individuals.service';
import { AdminOrganisationsController } from './admin-organisations.controller';
import { AdminOrganisationsService } from './admin-organisations.service';
import { AdminReportsController } from './admin-reports.controller';
import { AdminReportsService } from './admin-reports.service';

@Module({
  imports: [UploadModule],
  controllers: [
    AdminController,
    AdminUsersController,
    AdminIndividualsController,
    AdminOrganisationsController,
    AdminReportsController,
  ],
  providers: [
    AdminService,
    AdminUsersService,
    AdminIndividualsService,
    AdminOrganisationsService,
    AdminReportsService,
  ],
})
export class AdminModule {}
