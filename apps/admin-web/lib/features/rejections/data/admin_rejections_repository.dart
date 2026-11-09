import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// One "someone said no" event on a job or organisation requirement.
/// [event]: `caregiver_declined` (no reason is collected), `poster_rejected`
/// (free-text reason from the patient/organisation/admin) or
/// `caregiver_closed` (fixed close-reason key from the caregiver).
class AdminRejectionItem {
  final String kind;
  final String applicationId;
  final String event;
  final String occurredAt;
  final String? reason;
  final String caregiverProfileId;
  final int? caregiverNumber;
  final String caregiverName;
  final String caregiverPhone;
  final int? adminJobNumber;
  final int? patientJobNumber;
  final int? requirementNumber;
  final String? posterName;
  final String? posterPhone;
  final String? posterRole;
  final int? posterNumber;
  final String? decidedByName;
  final String? decidedByRole;

  const AdminRejectionItem({
    required this.kind,
    required this.applicationId,
    required this.event,
    required this.occurredAt,
    this.reason,
    required this.caregiverProfileId,
    this.caregiverNumber,
    required this.caregiverName,
    required this.caregiverPhone,
    this.adminJobNumber,
    this.patientJobNumber,
    this.requirementNumber,
    this.posterName,
    this.posterPhone,
    this.posterRole,
    this.posterNumber,
    this.decidedByName,
    this.decidedByRole,
  });

  String? get caregiverDisplayLabel => caregiverDisplayId(caregiverNumber);

  /// `ADMIN-JOB-n` / `PAT-JOB-n` / `ORG-JOB-n`, same text as every other screen.
  String get jobLabel {
    if (adminJobNumber != null) return 'ADMIN-JOB-$adminJobNumber';
    if (patientJobNumber != null) return 'PAT-JOB-$patientJobNumber';
    if (requirementNumber != null) return 'ORG-JOB-$requirementNumber';
    return '-';
  }

  String? get posterDisplayLabel => posterRole == 'organisation'
      ? organisationDisplayId(posterNumber)
      : patientDisplayId(posterNumber);

  factory AdminRejectionItem.fromJson(Map<String, dynamic> json) => AdminRejectionItem(
        kind: json['kind'] as String,
        applicationId: json['application_id'] as String,
        event: json['event'] as String,
        occurredAt: json['occurred_at'] as String,
        reason: json['reason'] as String?,
        caregiverProfileId: json['caregiver_profile_id'] as String,
        caregiverNumber: json['caregiver_number'] as int?,
        caregiverName: json['caregiver_name'] as String,
        caregiverPhone: json['caregiver_phone'] as String,
        adminJobNumber: json['admin_job_number'] as int?,
        patientJobNumber: json['patient_job_number'] as int?,
        requirementNumber: json['requirement_number'] as int?,
        posterName: json['poster_name'] as String?,
        posterPhone: json['poster_phone'] as String?,
        posterRole: json['poster_role'] as String?,
        posterNumber: json['poster_number'] as int?,
        decidedByName: json['decided_by_name'] as String?,
        decidedByRole: json['decided_by_role'] as String?,
      );
}

class AdminRejectionsListResult {
  final List<AdminRejectionItem> items;
  final PaginationMeta meta;

  const AdminRejectionsListResult({required this.items, required this.meta});
}

class AdminRejectionsRepository {
  final Dio _dio;

  AdminRejectionsRepository(this._dio);

  Future<AdminRejectionsListResult> list({
    int page = 1,
    int limit = 20,
    String? direction,
    String? search,
  }) async {
    try {
      final res = await _dio.get('/admin/rejections', queryParameters: {
        'page': page,
        'limit': limit,
        if (direction != null) 'direction': direction,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final items = (res.data['data'] as List)
          .map((item) => AdminRejectionItem.fromJson(item as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminRejectionsListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
