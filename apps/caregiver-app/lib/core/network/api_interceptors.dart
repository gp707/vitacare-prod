import 'package:dio/dio.dart';

import '../storage/local_storage.dart';

/// Attaches the caregiver's access token to every outgoing request.
/// Endpoints under /auth are public and simply ignore the header if present.
class AuthInterceptor extends Interceptor {
  final LocalStorage localStorage;

  AuthInterceptor(this.localStorage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = localStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
