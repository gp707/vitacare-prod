import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class JobSettingsWithUpdater {
  final int applyByWindowDays;
  final String? updatedByName;
  final String? updatedAt;

  const JobSettingsWithUpdater({
    required this.applyByWindowDays,
    this.updatedByName,
    this.updatedAt,
  });

  factory JobSettingsWithUpdater.fromJson(Map<String, dynamic> json) => JobSettingsWithUpdater(
        applyByWindowDays: json['apply_by_window_days'] as int,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String?,
      );
}

/// The apply-by urgency window shown on caregiver-app's job cards — see
/// JobModel.applyByDate/daysLeftToApply (packages/vitacare_shared) —
/// previously a hardcoded 3-day constant, now admin-configurable.
class JobSettingsRepository {
  final Dio _dio;

  JobSettingsRepository(this._dio);

  Future<JobSettingsWithUpdater> get() async {
    try {
      final res = await _dio.get('/admin/job-settings');
      return JobSettingsWithUpdater.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(int applyByWindowDays) async {
    try {
      await _dio.patch('/admin/job-settings', data: {'apply_by_window_days': applyByWindowDays});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
