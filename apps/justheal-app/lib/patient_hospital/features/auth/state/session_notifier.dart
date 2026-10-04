import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/jwt_decode.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/fcm/fcm_service.dart';
import '../../../core/storage/local_storage.dart';
import '../../individual/data/individual_repository.dart';
import '../../organisation/data/organisation_repository.dart';
import 'session_state.dart';

// tokenInvalidErrorCodes now lives in core/network/api_exception.dart,
// shared with AuthInterceptor.onError — see its own doc comment there.

/// Single source of truth for "who is logged in". Reused at splash
/// (loadSession) and right after register/login, since both cases just
/// need to read the token from storage and hydrate the right profile.
/// POST /auth/login/code is shared across Individual and Organisation
/// accounts and doesn't say which one in its response body, so the role is
/// decoded from the stored JWT's `role` claim first — if that fails to
/// decode (or isn't literally 'organisation'), this falls back to the
/// individual path, same as before role-awareness was added.
class SessionNotifier extends StateNotifier<SessionState> {
  final LocalStorage _localStorage;
  final IndividualRepository _individualRepository;
  final OrganisationRepository _organisationRepository;
  final FcmService _fcmService;

  SessionNotifier(
    this._localStorage,
    this._individualRepository,
    this._organisationRepository,
    this._fcmService,
  ) : super(const SessionLoading());

  bool _isOrganisationToken(String token) {
    try {
      return decodeJwtPayload(token)['role'] == 'organisation';
    } catch (_) {
      return false;
    }
  }

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
  /// not a transient failure.
  static const _maxAttempts = 3;

  Future<void> loadSession() async {
    final token = _localStorage.accessToken;
    if (token == null) {
      state = const SessionUnauthenticated();
      return;
    }
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final isOrganisation = _isOrganisationToken(token);
        if (isOrganisation) {
          final me = await _organisationRepository.getMe();
          state = SessionAuthenticated(
            role: 'organisation',
            fullName: me.contactPersonName,
            phone: me.phone,
            isJobPostingBlocked: me.isJobPostingBlocked,
            organisationName: me.organisationName,
            organisationType: me.organisationType,
            city: me.city,
            area: me.area,
            orgNumber: me.orgNumber,
          );
        } else {
          final me = await _individualRepository.getMe();
          state = SessionAuthenticated(
            role: 'individual',
            fullName: me.fullName,
            phone: me.phone,
            isJobPostingBlocked: me.isJobPostingBlocked,
            patientNumber: me.patientNumber,
          );
        }
        // Register on every app launch/login, not just once — mirrors
        // caregiver-app's own SessionNotifier.loadSession.
        unawaited(_fcmService.register(isOrganisation: isOrganisation));
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

  Future<void> logout() async {
    await _localStorage.clearTokens();
    state = const SessionUnauthenticated();
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(
    ref.watch(localStorageProvider),
    ref.watch(individualRepositoryProvider),
    ref.watch(organisationRepositoryProvider),
    ref.watch(fcmServiceProvider),
  );
});
