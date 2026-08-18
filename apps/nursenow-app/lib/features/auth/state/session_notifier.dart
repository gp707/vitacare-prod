import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/storage/local_storage.dart';
import '../../individual/data/individual_repository.dart';
import 'session_state.dart';

/// Single source of truth for "who is logged in". Reused at splash
/// (loadSession) and right after register/login, since both cases just
/// need to read the token from storage and hydrate from GET /individual/me.
class SessionNotifier extends StateNotifier<SessionState> {
  final LocalStorage _localStorage;
  final IndividualRepository _individualRepository;

  SessionNotifier(this._localStorage, this._individualRepository) : super(const SessionLoading());

  Future<void> loadSession() async {
    final token = _localStorage.accessToken;
    if (token == null) {
      state = const SessionUnauthenticated();
      return;
    }
    try {
      final me = await _individualRepository.getMe();
      state = SessionAuthenticated(
        fullName: me.fullName,
        phone: me.phone,
        isJobPostingBlocked: me.isJobPostingBlocked,
      );
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
  return SessionNotifier(ref.watch(localStorageProvider), ref.watch(individualRepositoryProvider));
});
