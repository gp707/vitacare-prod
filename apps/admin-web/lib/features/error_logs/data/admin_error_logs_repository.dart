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

  /// The sanitized request that triggered the error — `{query, params, body}`
  /// with PINs/tokens/OTPs already replaced by "[redacted]" server-side (see
  /// sanitizeRequestContext). Null when the request carried nothing.
  final Map<String, dynamic>? requestContext;
  final String? userAgent;

  /// 'open' or 'resolved' — resolving records who handled it, when, and a note.
  final String status;
  final String? resolvedAt;
  final String? resolvedByName;
  final String? resolutionNote;

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
    this.requestContext,
    this.userAgent,
    this.status = 'open',
    this.resolvedAt,
    this.resolvedByName,
    this.resolutionNote,
  });

  bool get isResolved => status == 'resolved';

  /// Whether there is a person behind this error that an admin can open/call.
  bool get hasCustomer => userId != null && userPhone != null;

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
        requestContext: json['request_context'] as Map<String, dynamic>?,
        userAgent: json['user_agent'] as String?,
        status: (json['status'] as String?) ?? 'open',
        resolvedAt: json['resolved_at'] as String?,
        resolvedByName: json['resolved_by_name'] as String?,
        resolutionNote: json['resolution_note'] as String?,
      );
}

/// One person who has hit unexpected errors — the "who do I call" row.
class AffectedUser {
  final String userId;
  final String fullName;
  final String phone;
  final String role;
  final int? caregiverNumber;
  final String? caregiverProfileId;
  final int? patientNumber;
  final int? orgNumber;
  final String? organisationName;
  final int errorCount;
  final int openCount;
  final DateTime lastErrorAt;
  final String lastErrorId;
  final String lastMessage;
  final String lastRequest;

  const AffectedUser({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    this.caregiverNumber,
    this.caregiverProfileId,
    this.patientNumber,
    this.orgNumber,
    this.organisationName,
    required this.errorCount,
    required this.openCount,
    required this.lastErrorAt,
    required this.lastErrorId,
    required this.lastMessage,
    required this.lastRequest,
  });

  /// `NUR-500` / `PAT-500` / `ORG-500`, whichever applies.
  String? get displayId =>
      caregiverDisplayId(caregiverNumber) ?? patientDisplayId(patientNumber) ?? organisationDisplayId(orgNumber);

  factory AffectedUser.fromJson(Map<String, dynamic> json) => AffectedUser(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        role: json['role'] as String,
        caregiverNumber: json['caregiver_number'] as int?,
        caregiverProfileId: json['caregiver_profile_id'] as String?,
        patientNumber: json['patient_number'] as int?,
        orgNumber: json['org_number'] as int?,
        organisationName: json['organisation_name'] as String?,
        errorCount: json['error_count'] as int,
        openCount: json['open_count'] as int,
        lastErrorAt: DateTime.parse(json['last_error_at'] as String),
        lastErrorId: json['last_error_id'] as String,
        lastMessage: json['last_message'] as String,
        lastRequest: json['last_request'] as String,
      );
}

class AffectedUsersResult {
  final List<AffectedUser> items;
  final PaginationMeta meta;

  const AffectedUsersResult({required this.items, required this.meta});
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

  /// [status] is 'open', 'resolved' or 'all'. [userId] narrows to one
  /// person's errors; [search] matches the request path or the message.
  Future<AdminErrorLogsListResult> list({
    int page = 1,
    int limit = 20,
    String status = 'all',
    String? userId,
    String? search,
  }) async {
    try {
      final res = await _dio.get('/admin/error-logs', queryParameters: {
        'page': page,
        'limit': limit,
        'status': status,
        if (userId != null) 'user_id': userId,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      });
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

  /// Everyone who has hit an unexpected error, most recent first.
  Future<AffectedUsersResult> listAffectedUsers({int page = 1, int limit = 20, String status = 'open'}) async {
    try {
      final res = await _dio
          .get('/admin/error-logs/affected-users', queryParameters: {'page': page, 'limit': limit, 'status': status});
      final items =
          (res.data['data'] as List).map((item) => AffectedUser.fromJson(item as Map<String, dynamic>)).toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AffectedUsersResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Marks one error handled, with an optional note.
  Future<void> resolve(String id, {String? note}) async {
    try {
      await _dio.patch('/admin/error-logs/$id/resolve', data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// "I called them" — resolves every open error for one person. Returns how
  /// many were resolved.
  Future<int> resolveAllForUser(String userId, {String? note}) async {
    try {
      final res = await _dio.patch('/admin/error-logs/users/$userId/resolve',
          data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()});
      return (res.data['data'] as Map<String, dynamic>)['resolved_count'] as int;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
