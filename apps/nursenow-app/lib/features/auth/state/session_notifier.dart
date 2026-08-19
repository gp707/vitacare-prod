import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/jwt_decode.dart';
import '../../../core/providers.dart';
import '../../../core/storage/local_storage.dart';
import '../../individual/data/individual_repository.dart';
import '../../organisation/data/organisation_repository.dart';
import 'session_state.dart';

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

  SessionNotifier(this._localStorage, this._individualRepository, this._organisationRepository)
      : super(const SessionLoading());

  bool _isOrganisationToken(String token) {
    try {
      return decodeJwtPayload(token)['role'] == 'organisation';
    } catch (_) {
      return false;
    }
  }

  Future<void> loadSession() async {
    final token = _localStorage.accessToken;
    if (token == null) {
      state = const SessionUnauthenticated();
      return;
    }
    try {
      if (_isOrganisationToken(token)) {
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
    } catch (_) {
      await _localStorage.clearTokens();
      state = const SessionUnauthenticated();
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
  );
});
