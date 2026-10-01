import 'package:dio/dio.dart';

import '../storage/local_storage.dart';
import 'api_exception.dart';

/// Attaches the caregiver's access token to every outgoing request.
/// Endpoints under /auth are public and simply ignore the header if present.
/// Also watches every response for an invalid/expired token (AUTH_004/
/// AUTH_005) — unlike loadSession's own check (splash-time only), this
/// catches it mid-session, on whichever request happens to hit it first,
/// and invokes [onUnauthorized] so the app can log out and redirect to
/// /login immediately instead of leaving the caregiver stuck on a screen
/// that silently keeps failing.
class AuthInterceptor extends Interceptor {
  final LocalStorage localStorage;
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
    final code = ApiException.fromDioException(err).code;
    if (tokenInvalidErrorCodes.contains(code)) {
      onUnauthorized?.call();
    }
    handler.next(err);
  }
}
