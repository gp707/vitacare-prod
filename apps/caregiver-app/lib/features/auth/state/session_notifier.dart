import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/fcm/fcm_service.dart';
import '../../../core/storage/local_storage.dart';
import '../../profile/data/profile_repository.dart';
import 'session_state.dart';

/// Error codes that mean the token itself is no longer good for anything —
/// a genuinely invalid/expired token, or the account behind it deleted or
/// deactivated (see JwtAuthGuard, apps/api). Only these actually warrant
/// clearing the stored token and forcing a fresh login; every other error
/// loadSession can hit (no connectivity, the backend briefly unreachable,
/// a 5xx) says nothing about the token's validity.
const _tokenInvalidErrorCodes = {'AUTH_004', 'AUTH_005'};

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
    } on ApiException catch (e) {
      if (_tokenInvalidErrorCodes.contains(e.code)) {
        await _localStorage.clearTokens();
        state = const SessionUnauthenticated();
      } else {
        // Server-side error (5xx, GEN_003 network-unreachable, ...) — the
        // token is left in storage; loadSession can simply be called again.
        state = SessionLoadError(e.message);
      }
    } catch (_) {
      // Anything not already wrapped as an ApiException (e.g. no
      // connectivity at all) — same fail-open treatment.
      state = const SessionLoadError('Could not reach the server. Please check your connection and try again.');
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
