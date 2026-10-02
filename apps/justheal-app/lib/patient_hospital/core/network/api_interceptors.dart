import 'package:dio/dio.dart';

import '../storage/local_storage.dart';
import 'api_exception.dart';

/// Attaches the individual's access token to every outgoing request, and
/// reacts to the server rejecting that token (AUTH_004/AUTH_005 — see
/// tokenInvalidErrorCodes in session_notifier.dart) from ANY call, not just
/// the one loadSession makes at splash. Endpoints under /auth are public
/// and simply ignore the header if present, and never return those codes
/// (JwtAuthGuard only runs on protected routes), so this never misfires
/// during login/registration itself.
class AuthInterceptor extends Interceptor {
  final LocalStorage localStorage;

  /// Fire-and-forget — clears the token and flips the app's session state
  /// to unauthenticated (see providers.dart's apiClientProvider, which
  /// wires this to sessionProvider.notifier.logout()). Deliberately not
  /// awaited here: the original error must still propagate immediately to
  /// whichever screen made the call, so its own error handling (retry/
  /// snackbar) isn't held up waiting on this side effect.
  final void Function()? onUnauthorized;

  AuthInterceptor(this.localStorage, {this.onUnauthorized});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = localStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final apiException = ApiException.fromDioException(err);
    if (tokenInvalidErrorCodes.contains(apiException.code)) {
      onUnauthorized?.call();
    }
    handler.next(err);
  }
}
