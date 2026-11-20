import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// One caregiver accepted onto a job or organisation requirement, with what has
/// happened since. [status] is the application's current status: `accepted` (still on
/// it), `completed` (the caregiver closed duty), `rejected` (accepted, then let go or
/// declined later) or `applied` (re-applied afterwards).
class AdminAcceptedItem {
  final String kind;
  final String applicationId;
  final String status;
  final String acceptedAt;
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
  /// Only known while still accepted/completed (a later rejection overwrites it).
  final String? acceptedByName;
  final String? acceptedByRole;
  final int? agreedSalary;
  /// 'daily' or 'monthly'.
  final String? agreedSalaryUnit;
  /// The cycle start date the patient agreed (YYYY-MM-DD), jobs only.
  final String? agreedStartDate;

  const AdminAcceptedItem({
    required this.kind,
    required this.applicationId,
    required this.status,
    required this.acceptedAt,
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
    this.acceptedByName,
    this.acceptedByRole,
    this.agreedSalary,
    this.agreedSalaryUnit,
    this.agreedStartDate,
  });

  String? get caregiverDisplayLabel => caregiverDisplayId(caregiverNumber);

  /// `ADMIN-JOB-n` / `PAT-JOB-n` / `ORG-JOB-n`, same text as every other screen.
  String get jobLabel {
    if (adminJobNumber != null) return 'ADMIN-JOB-$adminJobNumber';
    if (patientJobNumber != null) return 'PAT-JOB-$patientJobNumber';
    if (requirementNumber != null) return 'ORG-JOB-$requirementNumber';
    return '-';
  }

  String? get posterDisplayLabel =>
      posterRole == 'organisation' ? organisationDisplayId(posterNumber) : patientDisplayId(posterNumber);

  /// "₹30,000 per month" when the patient has agreed a salary, else null.
  String? get agreedSalaryText {
    final salary = agreedSalary;
    if (salary == null) return null;
    return '₹${formatRupees(salary)} per ${agreedSalaryUnit == 'daily' ? 'day' : 'month'}';
  }

  factory AdminAcceptedItem.fromJson(Map<String, dynamic> json) => AdminAcceptedItem(
        kind: json['kind'] as String,
        applicationId: json['application_id'] as String,
        status: json['status'] as String,
        acceptedAt: json['accepted_at'] as String,
        caregiverProfileId: json['caregiver_profile_id'] as String,
        caregiverNumber: (json['caregiver_number'] as num?)?.toInt(),
        caregiverName: json['caregiver_name'] as String,
        caregiverPhone: json['caregiver_phone'] as String,
        adminJobNumber: (json['admin_job_number'] as num?)?.toInt(),
        patientJobNumber: (json['patient_job_number'] as num?)?.toInt(),
        requirementNumber: (json['requirement_number'] as num?)?.toInt(),
        posterName: json['poster_name'] as String?,
        posterPhone: json['poster_phone'] as String?,
        posterRole: json['poster_role'] as String?,
        posterNumber: (json['poster_number'] as num?)?.toInt(),
        acceptedByName: json['accepted_by_name'] as String?,
        acceptedByRole: json['accepted_by_role'] as String?,
        agreedSalary: (json['agreed_salary'] as num?)?.toInt(),
        agreedSalaryUnit: json['agreed_salary_unit'] as String?,
        agreedStartDate: json['agreed_start_date'] as String?,
      );
}

class AdminAcceptedListResult {
  final List<AdminAcceptedItem> items;
  final PaginationMeta meta;

  const AdminAcceptedListResult({required this.items, required this.meta});
}

class AdminAcceptedRepository {
  final Dio _dio;

  AdminAcceptedRepository(this._dio);

  Future<AdminAcceptedListResult> list({int page = 1, int limit = 20, String? status, String? search}) async {
    try {
      final res = await _dio.get('/admin/accepted', queryParameters: {
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final items = (res.data['data'] as List)
          .map((item) => AdminAcceptedItem.fromJson(item as Map<String, dynamic>))
          .toList();
      final meta = PaginationMeta.fromJson(res.data['meta'] as Map<String, dynamic>);
      return AdminAcceptedListResult(items: items, meta: meta);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
