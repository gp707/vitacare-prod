import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/jwt_decode.dart';
import '../../../core/providers.dart';
import '../../../core/storage/local_storage.dart';
import 'session_state.dart';

/// Reads the role claim out of the locally-stored JWT — there is no
/// GET /admin/profile endpoint to hydrate session state from (see
/// core/jwt_decode.dart for why this is safe: the server still enforces
/// auth on every request regardless of what the client believes).
class SessionNotifier extends StateNotifier<AdminSessionState> {
  final LocalStorage _localStorage;

  SessionNotifier(this._localStorage) : super(const AdminSessionLoading());

  Future<void> loadSession() async {
    final token = _localStorage.accessToken;
    if (token == null) {
      state = const AdminSessionUnauthenticated();
      return;
    }
    try {
      if (isJwtExpired(token)) {
        await _localStorage.clearTokens();
        state = const AdminSessionUnauthenticated();
        return;
      }
      final payload = decodeJwtPayload(token);
      state = AdminSessionAuthenticated(
        userId: payload['sub'] as String,
        role: payload['role'] as String,
      );
    } catch (_) {
      await _localStorage.clearTokens();
      state = const AdminSessionUnauthenticated();
    }
  }

  Future<void> logout() async {
    await _localStorage.clearTokens();
    state = const AdminSessionUnauthenticated();
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, AdminSessionState>((ref) {
  return SessionNotifier(ref.watch(localStorageProvider));
});
