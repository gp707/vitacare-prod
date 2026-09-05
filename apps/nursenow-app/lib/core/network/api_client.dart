import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/local_storage.dart';
import 'api_interceptors.dart';

/// Same backend as NurseJobs (caregiver-app) — SPEC.md section 6.1:
/// Production https://api.vitacasahealth.in/v1, Development
/// http://localhost:3000/v1.
const String _productionBaseUrl = 'https://api.vitacasahealth.in/v1';
const String _developmentBaseUrl = 'http://localhost:3000/v1';

class ApiClient {
  final Dio dio;

  ApiClient._(this.dio);

  /// [onUnauthorized] fires when any request comes back with a token-invalid
  /// error (AUTH_004/AUTH_005 — see tokenInvalidErrorCodes) — wired in
  /// providers.dart to sessionProvider.notifier.logout(), so a token
  /// invalidated mid-session (not just at splash) still forces a logout.
  factory ApiClient(LocalStorage localStorage, {void Function()? onUnauthorized}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: kReleaseMode ? _productionBaseUrl : _developmentBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    dio.interceptors.add(AuthInterceptor(localStorage, onUnauthorized: onUnauthorized));
    return ApiClient._(dio);
  }
}
