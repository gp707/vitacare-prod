import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class AuthConfigRepository {
  final Dio _dio;

  AuthConfigRepository(this._dio);

  /// Called once on every cold launch, before the splash screen loads the
  /// session — same unauthenticated, checked-before-login shape as
  /// caregiver-app's AuthConfigRepository (nursenow has no equivalent
  /// pre-check to piggyback on otherwise). Deliberately fails open to
  /// `false` (PIN mode) on any error: a broken settings check must never
  /// be the thing that locks individuals/organisations out of logging in.
  Future<bool> isOtpEnabled() async {
    try {
      final res = await _dio.get(ApiRoutes.otpSettingsCheck, queryParameters: {'app': LoginApp.nursenow});
      return (res.data['data'] as Map<String, dynamic>)['enabled'] == true;
    } catch (_) {
      return false;
    }
  }
}
