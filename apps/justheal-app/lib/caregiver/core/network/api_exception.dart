import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

/// Error codes that mean the token itself is no longer good for anything —
/// a genuinely invalid/expired token, or the account behind it deleted or
/// deactivated (see JwtAuthGuard, apps/api). Lives here (not
/// session_notifier.dart, which also uses it) to avoid a circular import
/// between core/network and features/auth.
const tokenInvalidErrorCodes = {'AUTH_004', 'AUTH_005'};

/// Wraps the API's { success: false, error: { code, message } } envelope so
/// screens can branch on [code] and fall back to the server's [message].
class ApiException implements Exception {
  final String code;
  final String message;

  const ApiException({required this.code, required this.message});

  factory ApiException.fromDioException(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      final code = err['code'] as String? ?? 'GEN_003';
      final message = err['message'] as String? ?? ErrorCodes.messageFor(code);
      return ApiException(code: code, message: message);
    }
    return const ApiException(
      code: 'GEN_003',
      message: 'Could not reach the server. Please check your connection and try again.',
    );
  }

  @override
  String toString() => message;
}
