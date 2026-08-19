import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminOrganisationRequirement {
  final String id;
  final int requirementNumber;
  final String postedBy;
  final String typeOfNurse;
  final String? frequencyOfCare;
  final int? salaryAmount;
  /// Admin-set scheduling — exactly one mode, picked via [scheduleType].
  /// 'date_range' uses [startDate]/[endDate]; 'specific_days' uses
  /// [scheduleRepeat] + [specificDays] (weekdays 1-7 if weekly, days of
  /// month 1-31 if monthly). Null until approved.
  final String? scheduleType;
  final String? startDate;
  final String? endDate;
  final String? scheduleRepeat;
  final List<int>? specificDays;
  final bool accommodationProvided;
  final bool foodProvided;
  final String? specialSkills;
  final String status;
  final String? rejectionReason;
  final String postedAt;
  final String? organisationName;
  final String? organisationType;
  final String? city;
  final String? area;

  const AdminOrganisationRequirement({
    required this.id,
    required this.requirementNumber,
    required this.postedBy,
    required this.typeOfNurse,
    this.frequencyOfCare,
    this.salaryAmount,
    this.scheduleType,
    this.startDate,
    this.endDate,
    this.scheduleRepeat,
    this.specificDays,
    required this.accommodationProvided,
    required this.foodProvided,
    this.specialSkills,
    required this.status,
    this.rejectionReason,
    required this.postedAt,
    this.organisationName,
    this.organisationType,
    this.city,
    this.area,
  });

  factory AdminOrganisationRequirement.fromJson(Map<String, dynamic> json) => AdminOrganisationRequirement(
        id: json['id'] as String,
        requirementNumber: json['requirement_number'] as int,
        postedBy: json['posted_by'] as String,
        typeOfNurse: json['type_of_nurse'] as String,
        frequencyOfCare: json['frequency_of_care'] as String?,
        salaryAmount: json['salary_amount'] as int?,
        scheduleType: json['schedule_type'] as String?,
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        scheduleRepeat: json['schedule_repeat'] as String?,
        specificDays:
            json['specific_days'] != null ? List<int>.from(json['specific_days'] as List) : null,
        accommodationProvided: json['accommodation_provided'] as bool,
        foodProvided: json['food_provided'] as bool,
        specialSkills: json['special_skills'] as String?,
        status: json['status'] as String,
        rejectionReason: json['rejection_reason'] as String?,
        postedAt: json['posted_at'] as String,
        organisationName: json['organisation_name'] as String?,
        organisationType: json['organisation_type'] as String?,
        city: json['city'] as String?,
        area: json['area'] as String?,
      );
}

/// Mirrors AdminJobsRepository's shape for the pieces that apply here —
/// admin never *creates* an organisation requirement (the org posts its
/// own), only approves/edits/rejects and decides on applicants.
class AdminOrganisationRequirementsRepository {
  final Dio _dio;

  AdminOrganisationRequirementsRepository(this._dio);

  Future<List<AdminOrganisationRequirement>> list({String? status}) async {
    try {
      final res = await _dio.get(
        '/admin/organisation-requirements',
        queryParameters: {'limit': 100, if (status != null) 'status': status},
      );
      final items = res.data['data'] as List;
      return items.map((item) => AdminOrganisationRequirement.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Applications here are organisation_requirement_applications rows
  /// (requirement_id, not job_id) — OrganisationRequirementApplicationModel
  /// is the correctly-shaped model for this, NOT JobApplicationModel.
  Future<(AdminOrganisationRequirement, List<OrganisationRequirementApplicationModel>)> getDetail(String id) async {
    try {
      final res = await _dio.get('/admin/organisation-requirements/$id');
      final data = res.data['data'] as Map<String, dynamic>;
      final requirement = AdminOrganisationRequirement.fromJson(data);
      final applications = (data['applications'] as List)
          .map((item) => OrganisationRequirementApplicationModel.fromJson(item as Map<String, dynamic>))
          .toList();
      return (requirement, applications);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Approves (if pending_review) or edits (if already active) — same
  /// endpoint either way, matching JobsService.updateJob's repost pattern.
  /// [scheduleType] picks exactly one mode: 'date_range' (needs
  /// [startDate]/[endDate]) or 'specific_days' (needs [scheduleRepeat] +
  /// [specificDays]) — the other mode's fields are ignored server-side
  /// regardless of what's sent.
  Future<void> approve(
    String id, {
    required String typeOfNurse,
    required String frequencyOfCare,
    required int salaryAmount,
    required String scheduleType,
    String? startDate,
    String? endDate,
    String? scheduleRepeat,
    List<int>? specificDays,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
  }) async {
    try {
      await _dio.patch('/admin/organisation-requirements/$id', data: {
        'type_of_nurse': typeOfNurse,
        'frequency_of_care': frequencyOfCare,
        'salary_amount': salaryAmount,
        'schedule_type': scheduleType,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        if (scheduleRepeat != null) 'schedule_repeat': scheduleRepeat,
        if (specificDays != null) 'specific_days': specificDays,
        'accommodation_provided': accommodationProvided,
        'food_provided': foodProvided,
        if (specialSkills != null && specialSkills.isNotEmpty) 'special_skills': specialSkills,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> reject(String id, String reason) async {
    try {
      await _dio.patch('/admin/organisation-requirements/$id/reject', data: {'reason': reason});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> decideApplication(String requirementId, String applicationId, String status) async {
    try {
      await _dio.patch(
        '/admin/organisation-requirements/$requirementId/applications/$applicationId',
        data: {'status': status},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
