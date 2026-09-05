import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import 'audit_log_models.dart';

class AuditLogListFilters {
  final String? userId;
  final String? targetUserId;
  final String? action;
  final String? fromDate;
  final String? toDate;
  // Free-text — matches actor/target name/phone, the target's own display
  // id (NUR-/PAT-/ORG-<n>), entity_type, or the affected job/requirement's
  // display id (ADMIN-JOB-/PAT-JOB-/ORG-JOB-<n>). Same convention as every
  // other admin-web list screen's search filter.
  final String? search;
  final String order;
  final int page;
  final int limit;

  const AuditLogListFilters({
    this.userId,
    this.targetUserId,
    this.action,
    this.fromDate,
    this.toDate,
    this.search,
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
      if (search != null && search!.isNotEmpty) 'search': search,
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
      final res = await _dio.get('/admin/audit-logs',
          queryParameters: filters.toQueryParameters());
      final items = (res.data['data'] as List)
          .map((json) => AuditLogEntry.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta =
          PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AuditLogListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
