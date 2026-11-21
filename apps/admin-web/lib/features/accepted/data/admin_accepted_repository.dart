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
  /// The start date agreed with the caregiver (YYYY-MM-DD) — by the patient or the organisation.
  final String? agreedStartDate;
  /// The job / organisation requirement itself (to open it, and for the hover card).
  final String jobId;
  final String? jobCity;
  final String? jobArea;
  final String? jobShift;
  final String? jobTypeOfNurse;
  final String? jobSalary;
  final String? jobFrequency;
  /// The caregiver, for the hover card.
  final int? caregiverAge;
  final String? caregiverGender;
  final String? caregiverQualification;
  final String? caregiverStatus;
  /// The account that accepted (same availability as [acceptedByName]), to open their profile.
  final String? acceptedById;
  final String? acceptedByPhone;
  final int? acceptedByNumber;

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
    this.jobId = '',
    this.jobCity,
    this.jobArea,
    this.jobShift,
    this.jobTypeOfNurse,
    this.jobSalary,
    this.jobFrequency,
    this.caregiverAge,
    this.caregiverGender,
    this.caregiverQualification,
    this.caregiverStatus,
    this.acceptedById,
    this.acceptedByPhone,
    this.acceptedByNumber,
  });

  bool get isRequirement => kind == 'organisation_requirement';

  /// PAT-/ORG- id of whoever accepted; null for an admin or when it is no longer known.
  String? get acceptedByDisplayLabel => switch (acceptedByRole) {
        'individual' => patientDisplayId(acceptedByNumber),
        'organisation' => organisationDisplayId(acceptedByNumber),
        _ => null,
      };

  /// Only a patient/family or an organisation has a profile screen to open.
  bool get acceptedByHasProfile =>
      acceptedById != null && (acceptedByRole == 'individual' || acceptedByRole == 'organisation');

  /// Multi-line hover card for the caregiver cell.
  String get caregiverHoverText {
    final lines = <String>[
      '${caregiverDisplayLabel ?? 'Caregiver'} · $caregiverName',
      'Phone: $caregiverPhone',
      if (caregiverAge != null || caregiverGender != null)
        [
          if (caregiverAge != null) 'Age $caregiverAge',
          if (caregiverGender != null) Gender.displayNames[caregiverGender] ?? caregiverGender!,
        ].join(' · '),
      if (caregiverQualification != null)
        'Qualification: ${Qualification.displayNames[caregiverQualification] ?? caregiverQualification}',
      if (caregiverStatus != null) 'Status: ${caregiverStatus!.replaceAll('_', ' ')}',
      'Click to open their profile',
    ];
    return lines.join('\n');
  }

  /// Multi-line hover card for the job cell.
  String get jobHoverText {
    final where = [
      if (jobCity != null) City.displayNames[jobCity] ?? jobCity!,
      if (jobArea != null && jobArea!.isNotEmpty) jobArea!,
    ].join(' · ');
    final lines = <String>[
      jobLabel,
      if (posterName != null) 'Posted by: $posterName ${posterDisplayLabel ?? ''}'.trim(),
      if (where.isNotEmpty) where,
      if (jobShift != null) 'Shift: ${DutyType.displayNames[jobShift] ?? jobShift}',
      if (jobTypeOfNurse != null) 'Looking for: ${TypeOfNurse.displayNames[jobTypeOfNurse] ?? jobTypeOfNurse}',
      if (jobSalary != null && jobSalary!.isNotEmpty)
        'Offered: $jobSalary per ${jobFrequency == 'daily' ? 'day' : 'month'}',
      'Click to open this ${isRequirement ? 'requirement' : 'job'}',
    ];
    return lines.join('\n');
  }

  /// Multi-line hover card for the "Accepted by" cell.
  String get acceptedByHoverText {
    final role = switch (acceptedByRole) {
      'individual' => 'patient/family',
      'organisation' => 'organisation',
      'admin' || 'super_admin' => 'admin',
      _ => null,
    };
    final lines = <String>[
      [
        acceptedByName ?? '-',
        if (acceptedByDisplayLabel != null) acceptedByDisplayLabel!,
      ].join(' · '),
      if (role != null) 'Role: $role',
      if (acceptedByPhone != null) 'Phone: $acceptedByPhone',
      if (acceptedByHasProfile) 'Click to open their profile',
    ];
    return lines.join('\n');
  }

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
        jobId: (json['job_id'] as String?) ?? '',
        jobCity: json['job_city'] as String?,
        jobArea: json['job_area'] as String?,
        jobShift: json['job_shift'] as String?,
        jobTypeOfNurse: json['job_type_of_nurse'] as String?,
        jobSalary: json['job_salary'] as String?,
        jobFrequency: json['job_frequency'] as String?,
        caregiverAge: (json['caregiver_age'] as num?)?.toInt(),
        caregiverGender: json['caregiver_gender'] as String?,
        caregiverQualification: json['caregiver_qualification'] as String?,
        caregiverStatus: json['caregiver_status'] as String?,
        acceptedById: json['accepted_by_id'] as String?,
        acceptedByPhone: json['accepted_by_phone'] as String?,
        acceptedByNumber: (json['accepted_by_number'] as num?)?.toInt(),
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
