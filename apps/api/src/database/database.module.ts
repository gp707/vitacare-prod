import { Global, Module } from '@nestjs/common';
import { DatabaseService } from './database.service';
import { UsersRepository } from './repositories/users.repository';
import { CaregiverProfilesRepository } from './repositories/caregiver-profiles.repository';
import { CaregiverLanguagesRepository } from './repositories/caregiver-languages.repository';
import { CaregiverPreferredCitiesRepository } from './repositories/caregiver-preferred-cities.repository';
import { CaregiverPreferredDutyTypesRepository } from './repositories/caregiver-preferred-duty-types.repository';
import { IndividualProfilesRepository } from './repositories/individual-profiles.repository';
import { OrganisationProfilesRepository } from './repositories/organisation-profiles.repository';
import { OrganisationRequirementsRepository } from './repositories/organisation-requirements.repository';
import { OrganisationRequirementApplicationsRepository } from './repositories/organisation-requirement-applications.repository';
import { AdminIndividualsRepository } from './repositories/admin-individuals.repository';
import { AdminOrganisationsRepository } from './repositories/admin-organisations.repository';
import { RefreshTokensRepository } from './repositories/refresh-tokens.repository';
import { AdminCaregiversRepository } from './repositories/admin-caregivers.repository';
import { AdminNotesRepository } from './repositories/admin-notes.repository';
import { AuditLogsRepository } from './repositories/audit-logs.repository';
import { JobsRepository } from './repositories/jobs.repository';
import { JobApplicationsRepository } from './repositories/job-applications.repository';
import { CareReceiversRepository } from './repositories/care-receivers.repository';
import { AppMinVersionsRepository } from './repositories/app-min-versions.repository';
import { AdminReportsRepository } from './repositories/admin-reports.repository';
import { OtpAuthSettingsRepository } from './repositories/otp-auth-settings.repository';
import { OtpVerificationsRepository } from './repositories/otp-verifications.repository';
import { RateCardRepository } from './repositories/rate-card.repository';

const repositories = [
  UsersRepository,
  CaregiverProfilesRepository,
  CaregiverLanguagesRepository,
  CaregiverPreferredCitiesRepository,
  CaregiverPreferredDutyTypesRepository,
  IndividualProfilesRepository,
  OrganisationProfilesRepository,
  OrganisationRequirementsRepository,
  OrganisationRequirementApplicationsRepository,
  AdminIndividualsRepository,
  AdminOrganisationsRepository,
  RefreshTokensRepository,
  AdminCaregiversRepository,
  AdminNotesRepository,
  AuditLogsRepository,
  JobsRepository,
  JobApplicationsRepository,
  CareReceiversRepository,
  AppMinVersionsRepository,
  AdminReportsRepository,
  OtpAuthSettingsRepository,
  OtpVerificationsRepository,
  RateCardRepository,
];

@Global()
@Module({
  providers: [DatabaseService, ...repositories],
  exports: [DatabaseService, ...repositories],
})
export class DatabaseModule {}
