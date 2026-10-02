import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

class JobSettingsRepository {
  final Dio _dio;

  JobSettingsRepository(this._dio);

  /// Called once on every cold launch, same unauthenticated,
  /// checked-before-login shape as AppVersionRepository.checkForUpdate/
  /// AuthConfigRepository.isOtpEnabled. Deliberately fails open to
  /// Validation.applyByWindowDays on any error: a broken settings check
  /// must never break the apply-by urgency badge, it's purely informational.
  Future<int> getApplyByWindowDays() async {
    try {
      final res = await _dio.get(ApiRoutes.jobSettings);
      return (res.data['data'] as Map<String, dynamic>)['apply_by_window_days'] as int;
    } catch (_) {
      return Validation.applyByWindowDays;
    }
  }
}
