import { Module } from '@nestjs/common';
import { CaregiverModule } from '../caregiver/caregiver.module';
import { OrganisationController } from './organisation.controller';
import { CaregiverOrganisationRequirementsController } from './caregiver-organisation-requirements.controller';
import { AdminOrganisationRequirementsController } from './admin-organisation-requirements.controller';
import { OrganisationService } from './organisation.service';
import { OrganisationRequirementsService } from './organisation-requirements.service';

@Module({
  imports: [CaregiverModule],
  controllers: [
    OrganisationController,
    CaregiverOrganisationRequirementsController,
    AdminOrganisationRequirementsController,
  ],
  providers: [OrganisationService, OrganisationRequirementsService],
  exports: [OrganisationRequirementsService],
})
export class OrganisationModule {}
