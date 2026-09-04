import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class AuditLogRetentionWithUpdater {
  final int retentionDays;
  final String? updatedByName;
  final String? updatedAt;

  const AuditLogRetentionWithUpdater({
    required this.retentionDays,
    this.updatedByName,
    this.updatedAt,
  });

  factory AuditLogRetentionWithUpdater.fromJson(Map<String, dynamic> json) => AuditLogRetentionWithUpdater(
        retentionDays: json['retention_days'] as int,
        updatedByName: json['updated_by_name'] as String?,
        updatedAt: json['updated_at'] as String?,
      );
}

/// How many days of audit_logs stay in the live database before the
/// backend's daily sweep (AuditLogRetentionService.purgeExpiredLogs) hard-
/// deletes them — admin-only, no public/end-user-app counterpart.
class AuditLogRetentionRepository {
  final Dio _dio;

  AuditLogRetentionRepository(this._dio);

  Future<AuditLogRetentionWithUpdater> get() async {
    try {
      final res = await _dio.get('/admin/audit-log-retention');
      return AuditLogRetentionWithUpdater.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> update(int retentionDays) async {
    try {
      await _dio.patch('/admin/audit-log-retention', data: {'retention_days': retentionDays});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
