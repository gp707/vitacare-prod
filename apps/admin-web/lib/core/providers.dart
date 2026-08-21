import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/local_storage.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/dashboard/data/dashboard_repository.dart';
import '../features/caregivers/data/admin_caregivers_repository.dart';
import '../features/admin_management/data/admin_users_repository.dart';
import '../features/audit_logs/data/audit_logs_repository.dart';
import '../features/jobs/data/admin_jobs_repository.dart';
import '../features/app_versions/data/app_versions_repository.dart';
import '../features/individuals/data/admin_individuals_repository.dart';
import '../features/organisations/data/admin_organisations_repository.dart';
import '../features/organisation_requirements/data/admin_organisation_requirements_repository.dart';

/// Overridden in main.dart once the async LocalStorage.create() completes.
final localStorageProvider = Provider<LocalStorage>((ref) {
  throw UnimplementedError(
      'localStorageProvider must be overridden in main.dart');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(localStorageProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider).dio);
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(apiClientProvider).dio);
});

final adminCaregiversRepositoryProvider =
    Provider<AdminCaregiversRepository>((ref) {
  return AdminCaregiversRepository(ref.watch(apiClientProvider).dio);
});

final adminUsersRepositoryProvider = Provider<AdminUsersRepository>((ref) {
  return AdminUsersRepository(ref.watch(apiClientProvider).dio);
});

final auditLogsRepositoryProvider = Provider<AuditLogsRepository>((ref) {
  return AuditLogsRepository(ref.watch(apiClientProvider).dio);
});

final adminJobsRepositoryProvider = Provider<AdminJobsRepository>((ref) {
  return AdminJobsRepository(ref.watch(apiClientProvider).dio);
});

final appVersionsRepositoryProvider = Provider<AppVersionsRepository>((ref) {
  return AppVersionsRepository(ref.watch(apiClientProvider).dio);
});

final adminIndividualsRepositoryProvider =
    Provider<AdminIndividualsRepository>((ref) {
  return AdminIndividualsRepository(ref.watch(apiClientProvider).dio);
});

final adminOrganisationsRepositoryProvider =
    Provider<AdminOrganisationsRepository>((ref) {
  return AdminOrganisationsRepository(ref.watch(apiClientProvider).dio);
});

final adminOrganisationRequirementsRepositoryProvider =
    Provider<AdminOrganisationRequirementsRepository>((ref) {
  return AdminOrganisationRequirementsRepository(
      ref.watch(apiClientProvider).dio);
});
