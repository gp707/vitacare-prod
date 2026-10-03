import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
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

  /// The very first network call right after a cold app launch can fail
  /// transiently — the device's network/DNS stack isn't always fully ready
  /// in the first moment after the process starts (especially on an
  /// emulator), or the backend is just waking up from being idle — even
  /// though the exact same call succeeds a moment later with no other
  /// change. Rather than surface a scary "could not reach the server" to
  /// the user on every cold launch only for them to immediately tap Retry
  /// and have it work, this silently retries a couple of times with a
  /// short delay first. A genuinely invalid/expired token (caught below,
  /// before this loop) is never retried — that's a definitive rejection,
  /// not a transient failure. Mirrors patient_hospital's own
  /// SessionNotifier.loadSession.
  static const _maxAttempts = 3;

  Future<void> loadSession() async {
    final token = _localStorage.accessToken;
    if (token == null) {
      state = const SessionUnauthenticated();
      return;
    }
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
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
        return;
      } on ApiException catch (e) {
        if (tokenInvalidErrorCodes.contains(e.code)) {
          await _localStorage.clearTokens();
          state = const SessionUnauthenticated();
          return;
        }
        // Server-side error (5xx, GEN_003 network-unreachable, ...) —
        // retried below like any other transient failure; the token is
        // left in storage either way, so a later retry/relaunch can
        // simply call loadSession() again.
        if (attempt == _maxAttempts) {
          state = SessionLoadError(e.message);
          return;
        }
      } catch (_) {
        // Anything not already wrapped as an ApiException (e.g. no
        // connectivity at all) — same retry-then-fail-open treatment.
        if (attempt == _maxAttempts) {
          state = const SessionLoadError('Could not reach the server. Please check your connection and try again.');
          return;
        }
      }
      await Future.delayed(Duration(milliseconds: 400 * attempt));
    }
  }

  /// Cheap re-check used by pull-to-refresh and PendingCallScreen's own
  /// periodic auto-poll (avoids re-fetching the whole profile). Returns
  /// whether the check actually reached the server — pull-to-refresh uses
  /// this to tell the caregiver their attempt genuinely failed (e.g. poor
  /// mobile signal) instead of leaving them guessing why the status still
  /// looks unchanged; the periodic auto-poll ignores the return value
  /// entirely (a background tick failing silently and just trying again
  /// in another few seconds is the whole point of polling).
  Future<bool> refreshStatus() async {
    final current = state;
    if (current is! SessionAuthenticated) return false;
    try {
      final status = await _profileRepository.getVerificationStatus();
      state = current.copyWith(
        verificationStatus: status.verificationStatus,
        rejectionMessage: status.rejectionMessage,
      );
      return true;
    } catch (_) {
      return false;
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
