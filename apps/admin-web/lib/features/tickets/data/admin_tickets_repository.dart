import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminTicketItem {
  final String id;
  final String userId;
  final String userFullName;
  final String userRole;
  final int? caregiverNumber;
  final String? caregiverProfileId;
  final int? patientNumber;
  final int? orgNumber;
  final String type;
  final String status;
  final String phone;
  final String? notes;
  final String createdAt;
  final String? resolvedAt;
  final String? resolvedByName;

  const AdminTicketItem({
    required this.id,
    required this.userId,
    required this.userFullName,
    required this.userRole,
    this.caregiverNumber,
    this.caregiverProfileId,
    this.patientNumber,
    this.orgNumber,
    required this.type,
    required this.status,
    required this.phone,
    this.notes,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedByName,
  });

  /// "NUR-500" / "PAT-500" / "ORG-500", whichever applies to this
  /// requester's role — mirrors the shared display-id helpers.
  String? get displayId =>
      caregiverDisplayId(caregiverNumber) ?? patientDisplayId(patientNumber) ?? organisationDisplayId(orgNumber);

  factory AdminTicketItem.fromJson(Map<String, dynamic> json) => AdminTicketItem(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        userFullName: json['user_full_name'] as String,
        userRole: json['user_role'] as String,
        caregiverNumber: json['caregiver_number'] as int?,
        caregiverProfileId: json['caregiver_profile_id'] as String?,
        patientNumber: json['patient_number'] as int?,
        orgNumber: json['org_number'] as int?,
        type: json['type'] as String,
        status: json['status'] as String,
        phone: json['phone'] as String,
        notes: json['notes'] as String?,
        createdAt: json['created_at'] as String,
        resolvedAt: json['resolved_at'] as String?,
        resolvedByName: json['resolved_by_name'] as String?,
      );
}

class AdminTicketsListResult {
  final List<AdminTicketItem> items;
  final PaginationMeta meta;

  const AdminTicketsListResult({required this.items, required this.meta});
}

class AdminTicketsRepository {
  final Dio _dio;

  AdminTicketsRepository(this._dio);

  Future<AdminTicketsListResult> list({
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    try {
      final res = await _dio.get('/admin/tickets', queryParameters: {
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
      });
      final items = (res.data['data'] as List)
          .map((item) => AdminTicketItem.fromJson(item as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminTicketsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Only a still-open ticket can be resolved — the backend 400s
  /// (TICKET_001) otherwise.
  Future<void> resolve(String id, {String? notes}) async {
    try {
      await _dio.patch('/admin/tickets/$id/resolve', data: {
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
