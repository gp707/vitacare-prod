import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminErrorLogItem {
  final String id;
  final String method;
  final String path;
  final int statusCode;
  final String message;
  final String? stack;
  final String? userId;
  final String? userRole;
  final String? userFullName;
  final String? userPhone;
  final int? caregiverNumber;
  final String? caregiverProfileId;
  final int? patientNumber;
  final int? orgNumber;
  final String? ipAddress;
  final String createdAt;

  const AdminErrorLogItem({
    required this.id,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.message,
    this.stack,
    this.userId,
    this.userRole,
    this.userFullName,
    this.userPhone,
    this.caregiverNumber,
    this.caregiverProfileId,
    this.patientNumber,
    this.orgNumber,
    this.ipAddress,
    required this.createdAt,
  });

  /// "NUR-500" / "PAT-500" / "ORG-500", whichever applies — null if this
  /// error happened on an unauthenticated request (no user at all).
  String? get userDisplayId =>
      caregiverDisplayId(caregiverNumber) ?? patientDisplayId(patientNumber) ?? organisationDisplayId(orgNumber);

  factory AdminErrorLogItem.fromJson(Map<String, dynamic> json) => AdminErrorLogItem(
        id: json['id'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        statusCode: json['status_code'] as int,
        message: json['message'] as String,
        stack: json['stack'] as String?,
        userId: json['user_id'] as String?,
        userRole: json['user_role'] as String?,
        userFullName: json['user_full_name'] as String?,
        userPhone: json['user_phone'] as String?,
        caregiverNumber: json['caregiver_number'] as int?,
        caregiverProfileId: json['caregiver_profile_id'] as String?,
        patientNumber: json['patient_number'] as int?,
        orgNumber: json['org_number'] as int?,
        ipAddress: json['ip_address'] as String?,
        createdAt: json['created_at'] as String,
      );
}

class AdminErrorLogsListResult {
  final List<AdminErrorLogItem> items;
  final PaginationMeta meta;

  const AdminErrorLogsListResult({required this.items, required this.meta});
}

/// One day's request/error counters — see RequestStatsRepository on the
/// backend. A day with zero traffic simply has no entry in the list this
/// comes from.
class AdminDailyRequestStats {
  final String date;
  final int totalRequests;
  final int totalErrors;

  const AdminDailyRequestStats({
    required this.date,
    required this.totalRequests,
    required this.totalErrors,
  });

  factory AdminDailyRequestStats.fromJson(Map<String, dynamic> json) => AdminDailyRequestStats(
        date: json['date'] as String,
        totalRequests: json['total_requests'] as int,
        totalErrors: json['total_errors'] as int,
      );
}

class AdminErrorLogsRepository {
  final Dio _dio;

  AdminErrorLogsRepository(this._dio);

  Future<AdminErrorLogsListResult> list({int page = 1, int limit = 20}) async {
    try {
      final res = await _dio.get('/admin/error-logs', queryParameters: {'page': page, 'limit': limit});
      final items =
          (res.data['data'] as List).map((item) => AdminErrorLogItem.fromJson(item as Map<String, dynamic>)).toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminErrorLogsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Daily request/error counts for the last [days] calendar days
  /// (including today), oldest first.
  Future<List<AdminDailyRequestStats>> getStats({int days = 7}) async {
    try {
      final res = await _dio.get('/admin/error-logs/stats', queryParameters: {'days': days});
      return (res.data['data'] as List)
          .map((item) => AdminDailyRequestStats.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
