import 'package:dio/dio.dart';

import '../storage/local_storage.dart';

/// Attaches the admin's access token to every outgoing request, and tells the
/// app when the server says the session is over — the token has expired
/// (AUTH_005, e.g. a read-only admin's 4 hour session) or the account was
/// deactivated (AUTH_004) — so it can send the admin back to login instead of
/// leaving every screen failing one request at a time.
class AuthInterceptor extends Interceptor {
  final LocalStorage localStorage;
  final void Function()? onSessionEnded;

  AuthInterceptor(this.localStorage, {this.onSessionEnded});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 && onSessionEnded != null) {
      final data = err.response?.data;
      final code = data is Map && data['error'] is Map ? (data['error'] as Map)['code'] : null;
      if (code == 'AUTH_005' || code == 'AUTH_004') onSessionEnded!();
    }
    handler.next(err);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = localStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
