import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminIndividualListItem {
  final String userId;
  final int? patientNumber;
  final String fullName;
  final String phone;
  final bool isActive;
  final bool isJobPostingBlocked;
  final String? blockReason;
  final String createdAt;

  const AdminIndividualListItem({
    required this.userId,
    this.patientNumber,
    required this.fullName,
    required this.phone,
    required this.isActive,
    required this.isJobPostingBlocked,
    this.blockReason,
    required this.createdAt,
  });

  factory AdminIndividualListItem.fromJson(Map<String, dynamic> json) =>
      AdminIndividualListItem(
        userId: json['user_id'] as String,
        patientNumber: json['patient_number'] as int?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        isActive: json['is_active'] as bool,
        isJobPostingBlocked: json['is_job_posting_blocked'] as bool,
        blockReason: json['block_reason'] as String?,
        createdAt: json['created_at'] as String,
      );
}

class AdminIndividualsListResult {
  final List<AdminIndividualListItem> items;
  final PaginationMeta meta;

  const AdminIndividualsListResult({required this.items, required this.meta});
}

/// All fields optional/null = no filter applied for that field.
/// [blockStatus] is one of 'active' | 'job_posting_blocked' | 'blocked'.
class IndividualListFilters {
  final String? search;
  final String? blockStatus;

  const IndividualListFilters({this.search, this.blockStatus});

  Map<String, dynamic> toQueryParameters() => {
        if (search != null && search!.isNotEmpty) 'search': search,
        if (blockStatus != null) 'block_status': blockStatus,
      };
}

class AdminIndividualsRepository {
  final Dio _dio;

  AdminIndividualsRepository(this._dio);

  Future<AdminIndividualsListResult> list({
    int page = 1,
    int limit = 20,
    IndividualListFilters filters = const IndividualListFilters(),
  }) async {
    try {
      final res = await _dio.get(
        '/admin/individuals',
        queryParameters: {
          'page': page,
          'limit': limit,
          ...filters.toQueryParameters()
        },
      );
      final items = (res.data['data'] as List)
          .map((json) =>
              AdminIndividualListItem.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta =
          PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminIndividualsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Same shape as a list item — GET /admin/individuals/:id returns the
  /// identical fields, just for one account.
  Future<AdminIndividualListItem> getDetail(String userId) async {
    try {
      final res = await _dio.get('/admin/individuals/$userId');
      return AdminIndividualListItem.fromJson(
          res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Any subset of fields — only non-null entries in [fields] are sent.
  /// The only field an individual account actually has to edit is
  /// full_name (individual_profiles has no other profile-depth columns).
  Future<void> editProfile(String userId, Map<String, dynamic> fields) async {
    try {
      await _dio.put('/admin/individuals/$userId', data: fields);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [level] is 'job_posting' (blocks only new postings) or 'full' (login
  /// lockout, reuses users.is_active).
  Future<void> block(String userId, String level, String reason) async {
    try {
      await _dio.patch('/admin/individuals/$userId/block',
          data: {'level': level, 'reason': reason});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> unblock(String userId, String level) async {
    try {
      await _dio
          .patch('/admin/individuals/$userId/unblock', data: {'level': level});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
