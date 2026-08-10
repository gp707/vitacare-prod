import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/local_storage.dart';
import 'api_interceptors.dart';

/// SPEC.md section 6.1: Production https://api.vitacasahealth.in/v1,
/// Development http://localhost:3000/v1.
const String _productionBaseUrl = 'https://api.vitacasahealth.in/v1';
const String _developmentBaseUrl = 'http://localhost:3000/v1';

class ApiClient {
  final Dio dio;

  ApiClient._(this.dio);

  factory ApiClient(LocalStorage localStorage) {
    final dio = Dio(
      BaseOptions(
        baseUrl: kReleaseMode ? _productionBaseUrl : _developmentBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    dio.interceptors.add(AuthInterceptor(localStorage));
    return ApiClient._(dio);
  }
}
