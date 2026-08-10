import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import 'audit_log_models.dart';

class AuditLogListFilters {
  final String? userId;
  final String? targetUserId;
  final String? action;
  final String? fromDate;
  final String? toDate;
  final String order;
  final int page;
  final int limit;

  const AuditLogListFilters({
    this.userId,
    this.targetUserId,
    this.action,
    this.fromDate,
    this.toDate,
    this.order = 'desc',
    this.page = 1,
    this.limit = 20,
  });

  Map<String, dynamic> toQueryParameters() {
    return {
      'page': page,
      'limit': limit,
      'order': order,
      if (userId != null) 'user_id': userId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (action != null) 'action': action,
      if (fromDate != null) 'from_date': fromDate,
      if (toDate != null) 'to_date': toDate,
    };
  }
}

class AuditLogListResult {
  final List<AuditLogEntry> items;
  final PaginationMeta meta;

  const AuditLogListResult({required this.items, required this.meta});
}

class AuditLogsRepository {
  final Dio _dio;

  AuditLogsRepository(this._dio);

  Future<AuditLogListResult> list(AuditLogListFilters filters) async {
    try {
      final res = await _dio.get('/admin/audit-logs', queryParameters: filters.toQueryParameters());
      final items = (res.data['data'] as List)
          .map((json) => AuditLogEntry.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AuditLogListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
