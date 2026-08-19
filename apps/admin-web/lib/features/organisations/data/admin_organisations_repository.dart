import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminOrganisationListItem {
  final String userId;
  final int? orgNumber;
  final String fullName;
  final String phone;
  final String organisationName;
  final String organisationType;
  final String city;
  final String area;
  final bool isActive;
  final bool isJobPostingBlocked;
  final String? blockReason;
  final String createdAt;

  const AdminOrganisationListItem({
    required this.userId,
    this.orgNumber,
    required this.fullName,
    required this.phone,
    required this.organisationName,
    required this.organisationType,
    required this.city,
    required this.area,
    required this.isActive,
    required this.isJobPostingBlocked,
    this.blockReason,
    required this.createdAt,
  });

  factory AdminOrganisationListItem.fromJson(Map<String, dynamic> json) => AdminOrganisationListItem(
        userId: json['user_id'] as String,
        orgNumber: json['org_number'] as int?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        organisationName: json['organisation_name'] as String,
        organisationType: json['organisation_type'] as String,
        city: json['city'] as String,
        area: json['area'] as String,
        isActive: json['is_active'] as bool,
        isJobPostingBlocked: json['is_job_posting_blocked'] as bool,
        blockReason: json['block_reason'] as String?,
        createdAt: json['created_at'] as String,
      );
}

class AdminOrganisationsListResult {
  final List<AdminOrganisationListItem> items;
  final PaginationMeta meta;

  const AdminOrganisationsListResult({required this.items, required this.meta});
}

/// Mirrors AdminIndividualsRepository exactly.
class AdminOrganisationsRepository {
  final Dio _dio;

  AdminOrganisationsRepository(this._dio);

  Future<AdminOrganisationsListResult> list({int page = 1, int limit = 20}) async {
    try {
      final res = await _dio.get('/admin/organisations', queryParameters: {'page': page, 'limit': limit});
      final items = (res.data['data'] as List)
          .map((json) => AdminOrganisationListItem.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminOrganisationsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [level] is 'job_posting' (blocks only new postings) or 'full' (login
  /// lockout, reuses users.is_active).
  Future<void> block(String userId, String level, String reason) async {
    try {
      await _dio.patch('/admin/organisations/$userId/block', data: {'level': level, 'reason': reason});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> unblock(String userId, String level) async {
    try {
      await _dio.patch('/admin/organisations/$userId/unblock', data: {'level': level});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
