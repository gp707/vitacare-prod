import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/local_storage.dart';
import 'auth_config/auth_config_repository.dart';
import 'rate_card/rate_card_repository.dart';
import 'scope_of_work/scope_of_work_repository.dart';
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

final authConfigRepositoryProvider = Provider<AuthConfigRepository>((ref) {
  return AuthConfigRepository(ref.watch(apiClientProvider).dio);
});

final rateCardRepositoryProvider = Provider<RateCardRepository>((ref) {
  return RateCardRepository(ref.watch(apiClientProvider).dio);
});

final scopeOfWorkRepositoryProvider = Provider<ScopeOfWorkRepository>((ref) {
  return ScopeOfWorkRepository(ref.watch(apiClientProvider).dio);
});

/// Whether OTP mode is enabled for this app (nursenow) — set once at splash
/// time from AuthConfigRepository.isOtpEnabled(), read by LoginScreen/
/// RegistrationScreen to decide whether to show phone+OTP or phone+PIN.
/// Defaults to false (PIN mode), the known-safe default this falls back to
/// on any error.
final otpModeProvider = StateProvider<bool>((ref) => false);
