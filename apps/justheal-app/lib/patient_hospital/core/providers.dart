import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/local_storage.dart';
import 'auth_config/auth_config_repository.dart';
import 'version/app_version_repository.dart';
import 'version/app_maintenance_repository.dart';
import 'rate_card/rate_card_repository.dart';
import 'scope_of_work/scope_of_work_repository.dart';
import 'duty_requirements/duty_requirements_repository.dart';
import 'individual_messages/individual_messages_repository.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/individual/data/individual_repository.dart';
import '../features/organisation/data/organisation_repository.dart';

/// Overridden in main.dart once the async LocalStorage.create() completes.
final localStorageProvider = Provider<LocalStorage>((ref) {
  throw UnimplementedError('localStorageProvider must be overridden in main.dart');
});

// Explicitly typed (not just via the Provider<ApiClient> generic) to break
// a top-level type-inference cycle: this reads sessionProvider, which
// (through SessionNotifier's own constructor) reads individualRepositoryProvider/
// organisationRepositoryProvider, which read this same provider — Dart can't
// infer types around that cycle without one link in it being explicit.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(localStorageProvider),
    // ref.read, not ref.watch — this only needs to reach the notifier once
    // an error actually happens, not rebuild ApiClient whenever session
    // state changes (that would tear down/reattach the interceptor on
    // every login/logout for no reason).
    onUnauthorized: () => ref.read(sessionProvider.notifier).logout(),
  );
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

final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return AppVersionRepository(ref.watch(apiClientProvider).dio);
});

final appMaintenanceRepositoryProvider = Provider<AppMaintenanceRepository>((ref) {
  return AppMaintenanceRepository(ref.watch(apiClientProvider).dio);
});

final rateCardRepositoryProvider = Provider<RateCardRepository>((ref) {
  return RateCardRepository(ref.watch(apiClientProvider).dio);
});

final scopeOfWorkRepositoryProvider = Provider<ScopeOfWorkRepository>((ref) {
  return ScopeOfWorkRepository(ref.watch(apiClientProvider).dio);
});

final dutyRequirementsRepositoryProvider = Provider<DutyRequirementsRepository>((ref) {
  return DutyRequirementsRepository(ref.watch(apiClientProvider).dio);
});

final individualMessagesRepositoryProvider = Provider<IndividualMessagesRepository>((ref) {
  return IndividualMessagesRepository(ref.watch(apiClientProvider).dio);
});

/// Whether OTP mode is enabled for this app (nursenow) — set once at splash
/// time from AuthConfigRepository.isOtpEnabled(), read by LoginScreen/
/// RegistrationScreen to decide whether to show phone+OTP or phone+PIN.
/// Defaults to false (PIN mode), the known-safe default this falls back to
/// on any error.
final otpModeProvider = StateProvider<bool>((ref) => false);
