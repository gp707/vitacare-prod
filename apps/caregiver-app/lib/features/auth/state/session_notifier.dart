import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/fcm/fcm_service.dart';
import '../../../core/storage/local_storage.dart';
import '../../profile/data/profile_repository.dart';
import 'session_state.dart';

/// Single source of truth for "who is logged in and what's their status".
/// Reused at splash (loadSession) and right after register/login, since
/// both cases just need to read the token from storage and hydrate from
/// GET /caregiver/profile.
class SessionNotifier extends StateNotifier<SessionState> {
  final LocalStorage _localStorage;
  final ProfileRepository _profileRepository;
  final FcmService _fcmService;

  SessionNotifier(this._localStorage, this._profileRepository, this._fcmService)
      : super(const SessionLoading());

  Future<void> loadSession() async {
    final token = _localStorage.accessToken;
    if (token == null) {
      state = const SessionUnauthenticated();
      return;
    }
    try {
      final profile = await _profileRepository.getProfile();
      state = SessionAuthenticated(
        fullName: profile.fullName,
        phone: profile.phone,
        verificationStatus: profile.verificationStatus,
        hasRequiredDocuments: profile.hasRequiredDocuments,
        rejectionMessage: profile.rejectionMessage,
      );
      // SPEC.md 6.4: register on every app launch / login, not just once.
      unawaited(_fcmService.register());
    } catch (_) {
      await _localStorage.clearTokens();
      state = const SessionUnauthenticated();
    }
  }

  /// Cheap re-check used by pull-to-refresh (Pending Call / Verification
  /// Status screens) — avoids re-fetching the whole profile.
  Future<void> refreshStatus() async {
    final current = state;
    if (current is! SessionAuthenticated) return;
    try {
      final status = await _profileRepository.getVerificationStatus();
      state = current.copyWith(
        verificationStatus: status.verificationStatus,
        rejectionMessage: status.rejectionMessage,
      );
    } catch (_) {
      // Transient network errors on pull-to-refresh are silently ignored;
      // the user can just try again.
    }
  }

  Future<void> logout() async {
    await _localStorage.clearTokens();
    state = const SessionUnauthenticated();
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(
    ref.watch(localStorageProvider),
    ref.watch(profileRepositoryProvider),
    ref.watch(fcmServiceProvider),
  );
});
