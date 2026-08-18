import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminIndividualListItem {
  final String userId;
  final String fullName;
  final String phone;
  final bool isActive;
  final bool isJobPostingBlocked;
  final String? blockReason;
  final String createdAt;

  const AdminIndividualListItem({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.isActive,
    required this.isJobPostingBlocked,
    this.blockReason,
    required this.createdAt,
  });

  factory AdminIndividualListItem.fromJson(Map<String, dynamic> json) => AdminIndividualListItem(
        userId: json['user_id'] as String,
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

class AdminIndividualsRepository {
  final Dio _dio;

  AdminIndividualsRepository(this._dio);

  Future<AdminIndividualsListResult> list({int page = 1, int limit = 20}) async {
    try {
      final res = await _dio.get('/admin/individuals', queryParameters: {'page': page, 'limit': limit});
      final items = (res.data['data'] as List)
          .map((json) => AdminIndividualListItem.fromJson(json as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminIndividualsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [level] is 'job_posting' (blocks only new postings) or 'full' (login
  /// lockout, reuses users.is_active).
  Future<void> block(String userId, String level, String reason) async {
    try {
      await _dio.patch('/admin/individuals/$userId/block', data: {'level': level, 'reason': reason});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> unblock(String userId, String level) async {
    try {
      await _dio.patch('/admin/individuals/$userId/unblock', data: {'level': level});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
