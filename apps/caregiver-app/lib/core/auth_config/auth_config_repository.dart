import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class AuthConfigRepository {
  final Dio _dio;

  AuthConfigRepository(this._dio);

  /// Called once on every cold launch, before the splash screen loads the
  /// session — same unauthenticated, checked-before-login shape as
  /// AppVersionRepository.checkForUpdate. Deliberately fails open to
  /// `false` (PIN mode) on any error: a broken settings check must never
  /// be the thing that locks caregivers out of logging in at all.
  Future<bool> isOtpEnabled() async {
    try {
      final res = await _dio.get(ApiRoutes.otpSettingsCheck, queryParameters: {'app': LoginApp.nursejobs});
      return (res.data['data'] as Map<String, dynamic>)['enabled'] == true;
    } catch (_) {
      return false;
    }
  }
}
