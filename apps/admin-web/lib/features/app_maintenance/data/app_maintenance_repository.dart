import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

/// Singleton — one JustHeal binary now covers both the caregiver and
/// patient/hospital flows, so there's only one app to take down for
/// maintenance. Used to carry a per-app (NurseJobs/NurseNow) dimension
/// (migration 068); collapsed by migration 074 once they merged into one
/// binary (see CLAUDE.md's "Merged into one binary with NurseJobs").
class AppMaintenance {
  final bool enabled;
  final String? message;
  final String? updatedByName;
  final String updatedAt;

  const AppMaintenance({
    required this.enabled,
    this.message,
    this.updatedByName,
    required this.updatedAt,
  });

  factory AppMaintenance.fromJson(Map<String, dynamic> json) => AppMaintenance(
        enabled: json['enabled'] as bool,
        message: json['message'] as String?,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class AppMaintenanceRepository {
  final Dio _dio;

  AppMaintenanceRepository(this._dio);

  Future<AppMaintenance> get() async {
    try {
      final res = await _dio.get('/admin/app-maintenance');
      return AppMaintenance.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update({required bool enabled, String? message}) async {
    try {
      await _dio.patch('/admin/app-maintenance', data: {
        'enabled': enabled,
        if (message != null && message.isNotEmpty) 'message': message,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
