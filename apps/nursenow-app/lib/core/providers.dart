import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/local_storage.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/individual/data/individual_repository.dart';
import '../features/organisation/data/organisation_repository.dart';

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

final individualRepositoryProvider = Provider<IndividualRepository>((ref) {
  return IndividualRepository(ref.watch(apiClientProvider).dio);
});

final organisationRepositoryProvider = Provider<OrganisationRepository>((ref) {
  return OrganisationRepository(ref.watch(apiClientProvider).dio);
});
