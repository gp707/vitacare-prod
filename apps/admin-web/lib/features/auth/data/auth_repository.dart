import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminLoginResult {
  final String userId;
  final String accessToken;
  final String refreshToken;

  const AdminLoginResult({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AdminLoginResult.fromJson(Map<String, dynamic> json) =>
      AdminLoginResult(
        userId: json['user_id'] as String,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      );
}

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  Future<AdminLoginResult> loginEmail(String email, String password) async {
    try {
      final res = await _dio.post(ApiRoutes.loginEmail,
          data: {'email': email, 'password': password});
      return AdminLoginResult.fromJson(
          res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(ApiRoutes.logout);
    } on DioException {
      // Best-effort — the client clears its local session regardless.
    }
  }
}
