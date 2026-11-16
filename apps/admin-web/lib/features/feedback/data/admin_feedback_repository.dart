import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// One feedback left between a patient/family and a caregiver (read-only for admin).
class AdminFeedbackItem {
  final String id;
  /// 'individual' = the patient/family wrote about the caregiver; 'caregiver' = the reverse.
  final String authorRole;
  final int rating;
  final String? comment;
  final String createdAt;
  final String jobId;
  final int? adminJobNumber;
  final int? patientJobNumber;
  final int? caregiverNumber;
  final String caregiverProfileId;
  final String? caregiverName;
  final int? patientNumber;
  final String? patientUserId;
  final String? patientName;

  const AdminFeedbackItem({
    required this.id,
    required this.authorRole,
    required this.rating,
    this.comment,
    required this.createdAt,
    required this.jobId,
    this.adminJobNumber,
    this.patientJobNumber,
    this.caregiverNumber,
    required this.caregiverProfileId,
    this.caregiverName,
    this.patientNumber,
    this.patientUserId,
    this.patientName,
  });

  bool get byPatient => authorRole == 'individual';

  String get caregiverLabel => caregiverDisplayId(caregiverNumber) ?? 'Caregiver';
  String get patientLabel => patientDisplayId(patientNumber) ?? 'Patient/Family';

  /// "PAT-JOB-548" / "ADMIN-JOB-500".
  String? get jobLabel => patientJobNumber != null
      ? 'PAT-JOB-$patientJobNumber'
      : (adminJobNumber != null ? 'ADMIN-JOB-$adminJobNumber' : null);

  factory AdminFeedbackItem.fromJson(Map<String, dynamic> json) => AdminFeedbackItem(
        id: json['id'] as String,
        authorRole: json['author_role'] as String,
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: json['created_at'] as String,
        jobId: json['job_id'] as String,
        adminJobNumber: (json['admin_job_number'] as num?)?.toInt(),
        patientJobNumber: (json['patient_job_number'] as num?)?.toInt(),
        caregiverNumber: (json['caregiver_number'] as num?)?.toInt(),
        caregiverProfileId: json['caregiver_profile_id'] as String,
        caregiverName: json['caregiver_name'] as String?,
        patientNumber: (json['patient_number'] as num?)?.toInt(),
        patientUserId: json['patient_user_id'] as String?,
        patientName: json['patient_name'] as String?,
      );
}

class AdminFeedbackListResult {
  final List<AdminFeedbackItem> items;
  final PaginationMeta meta;

  const AdminFeedbackListResult({required this.items, required this.meta});
}

class AdminFeedbackRepository {
  final Dio _dio;

  AdminFeedbackRepository(this._dio);

  Future<AdminFeedbackListResult> list({int page = 1, int limit = 20, String? authorRole, int? rating, String? search}) async {
    try {
      final res = await _dio.get('/admin/feedback', queryParameters: {
        'page': page,
        'limit': limit,
        if (authorRole != null) 'author_role': authorRole,
        if (rating != null) 'rating': rating,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final items = (res.data['data'] as List)
          .map((item) => AdminFeedbackItem.fromJson(item as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminFeedbackListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
