import { Global, Module } from '@nestjs/common';
import { DatabaseService } from './database.service';
import { UsersRepository } from './repositories/users.repository';
import { CaregiverProfilesRepository } from './repositories/caregiver-profiles.repository';
import { CaregiverLanguagesRepository } from './repositories/caregiver-languages.repository';
import { CaregiverPreferredCitiesRepository } from './repositories/caregiver-preferred-cities.repository';
import { RefreshTokensRepository } from './repositories/refresh-tokens.repository';
import { AdminCaregiversRepository } from './repositories/admin-caregivers.repository';
import { AdminNotesRepository } from './repositories/admin-notes.repository';
import { AuditLogsRepository } from './repositories/audit-logs.repository';
import { JobsRepository } from './repositories/jobs.repository';
import { JobResponsesRepository } from './repositories/job-responses.repository';

const repositories = [
  UsersRepository,
  CaregiverProfilesRepository,
  CaregiverLanguagesRepository,
  CaregiverPreferredCitiesRepository,
  RefreshTokensRepository,
  AdminCaregiversRepository,
  AdminNotesRepository,
  AuditLogsRepository,
  JobsRepository,
  JobResponsesRepository,
];

@Global()
@Module({
  providers: [DatabaseService, ...repositories],
  exports: [DatabaseService, ...repositories],
})
export class DatabaseModule {}
