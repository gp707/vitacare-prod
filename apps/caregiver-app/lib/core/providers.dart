import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/local_storage.dart';
import 'fcm/fcm_service.dart';
import 'version/app_version_repository.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/jobs/data/jobs_repository.dart';
import '../features/organisation_openings/data/organisation_openings_repository.dart';

/// Overridden in main.dart once the async LocalStorage.create() completes.
final localStorageProvider = Provider<LocalStorage>((ref) {
  throw UnimplementedError('localStorageProvider must be overridden in main.dart');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(localStorageProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider).dio);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider).dio);
});

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref.watch(profileRepositoryProvider));
});

final jobsRepositoryProvider = Provider<JobsRepository>((ref) {
  return JobsRepository(ref.watch(apiClientProvider).dio);
});

final organisationOpeningsRepositoryProvider = Provider<OrganisationOpeningsRepository>((ref) {
  return OrganisationOpeningsRepository(ref.watch(apiClientProvider).dio);
});

final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return AppVersionRepository(ref.watch(apiClientProvider).dio);
});
