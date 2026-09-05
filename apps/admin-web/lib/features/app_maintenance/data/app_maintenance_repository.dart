import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class AppMaintenance {
  final String app;
  final bool enabled;
  final String? message;
  final String? updatedByName;
  final String updatedAt;

  const AppMaintenance({
    required this.app,
    required this.enabled,
    this.message,
    this.updatedByName,
    required this.updatedAt,
  });

  factory AppMaintenance.fromJson(Map<String, dynamic> json) => AppMaintenance(
        app: json['app'] as String,
        enabled: json['enabled'] as bool,
        message: json['message'] as String?,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}

class AppMaintenanceRepository {
  final Dio _dio;

  AppMaintenanceRepository(this._dio);

  /// Returns both app rows (NurseJobs + NurseNow) — each is independently
  /// editable/saveable, see migration 068.
  Future<List<AppMaintenance>> list() async {
    try {
      final res = await _dio.get('/admin/app-maintenance');
      return (res.data['data'] as List)
          .map((json) => AppMaintenance.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(String app, {required bool enabled, String? message}) async {
    try {
      await _dio.patch('/admin/app-maintenance/$app', data: {
        'enabled': enabled,
        if (message != null && message.isNotEmpty) 'message': message,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
