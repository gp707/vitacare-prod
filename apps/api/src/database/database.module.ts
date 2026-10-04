import { Global, Module } from '@nestjs/common';
import { DatabaseService } from './database.service';
import { UsersRepository } from './repositories/users.repository';
import { CaregiverProfilesRepository } from './repositories/caregiver-profiles.repository';
import { CaregiverDocumentsRepository } from './repositories/caregiver-documents.repository';
import { CaregiverLanguagesRepository } from './repositories/caregiver-languages.repository';
import { CaregiverPreferredCitiesRepository } from './repositories/caregiver-preferred-cities.repository';
import { IndividualProfilesRepository } from './repositories/individual-profiles.repository';
import { OrganisationProfilesRepository } from './repositories/organisation-profiles.repository';
import { OrganisationRequirementsRepository } from './repositories/organisation-requirements.repository';
import { OrganisationRequirementApplicationsRepository } from './repositories/organisation-requirement-applications.repository';
import { AdminIndividualsRepository } from './repositories/admin-individuals.repository';
import { AdminOrganisationsRepository } from './repositories/admin-organisations.repository';
import { RefreshTokensRepository } from './repositories/refresh-tokens.repository';
import { AdminCaregiversRepository } from './repositories/admin-caregivers.repository';
import { AdminNotesRepository } from './repositories/admin-notes.repository';
import { JobAdminNotesRepository } from './repositories/job-admin-notes.repository';
import { IndividualAdminNotesRepository } from './repositories/individual-admin-notes.repository';
import { AuditLogsRepository } from './repositories/audit-logs.repository';
import { JobsRepository } from './repositories/jobs.repository';
import { JobApplicationsRepository } from './repositories/job-applications.repository';
import { CareReceiversRepository } from './repositories/care-receivers.repository';
import { AppMinVersionsRepository } from './repositories/app-min-versions.repository';
import { AppMaintenanceRepository } from './repositories/app-maintenance.repository';
import { AdminReportsRepository } from './repositories/admin-reports.repository';
import { OtpAuthSettingsRepository } from './repositories/otp-auth-settings.repository';
import { OtpVerificationsRepository } from './repositories/otp-verifications.repository';
import { RateCardRepository } from './repositories/rate-card.repository';
import { ScopeOfWorkRepository } from './repositories/scope-of-work.repository';
import { DutyRequirementsRepository } from './repositories/duty-requirements.repository';
import { JobSettingsRepository } from './repositories/job-settings.repository';
import { IndividualMessagesRepository } from './repositories/individual-messages.repository';
import { CaregiverMessagesRepository } from './repositories/caregiver-messages.repository';
import { AuditLogRetentionRepository } from './repositories/audit-log-retention.repository';

const repositories = [
  UsersRepository,
  CaregiverProfilesRepository,
  CaregiverDocumentsRepository,
  CaregiverLanguagesRepository,
  CaregiverPreferredCitiesRepository,
  IndividualProfilesRepository,
  OrganisationProfilesRepository,
  OrganisationRequirementsRepository,
  OrganisationRequirementApplicationsRepository,
  AdminIndividualsRepository,
  AdminOrganisationsRepository,
  RefreshTokensRepository,
  AdminCaregiversRepository,
  AdminNotesRepository,
  JobAdminNotesRepository,
  IndividualAdminNotesRepository,
  AuditLogsRepository,
  JobsRepository,
  JobApplicationsRepository,
  CareReceiversRepository,
  AppMinVersionsRepository,
  AppMaintenanceRepository,
  AdminReportsRepository,
  OtpAuthSettingsRepository,
  OtpVerificationsRepository,
  RateCardRepository,
  ScopeOfWorkRepository,
  DutyRequirementsRepository,
  JobSettingsRepository,
  IndividualMessagesRepository,
  CaregiverMessagesRepository,
  AuditLogRetentionRepository,
];

@Global()
@Module({
  providers: [DatabaseService, ...repositories],
  exports: [DatabaseService, ...repositories],
})
export class DatabaseModule {}
