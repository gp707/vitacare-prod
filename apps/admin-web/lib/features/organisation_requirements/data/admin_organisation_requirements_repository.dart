import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminOrganisationRequirement {
  final String id;
  final int requirementNumber;
  final String postedBy;
  final String typeOfNurse;
  /// Free text elaboration, only ever non-null when [typeOfNurse] is
  /// 'others' — org-owned, admin never sets this, only ever sees/forwards
  /// it unchanged on approve/edit.
  final String? typeOfNurseOther;
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
  /// Org-set at creation, 1-49, defaults to 1 — how many caregivers this
  /// one requirement is looking to fill. Org-owned, same as above.
  final int numberOfVacancies;
  /// Org-set at creation. Null = no preference. Org-owned, same as above.
  final String? preferredGender;
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
    this.typeOfNurseOther,
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
    required this.numberOfVacancies,
    this.preferredGender,
    required this.status,
    this.rejectionReason,
    required this.postedAt,
    this.organisationName,
    this.organisationType,
    this.city,
    this.area,
  });

  factory AdminOrganisationRequirement.fromJson(Map<String, dynamic> json) =>
      AdminOrganisationRequirement(
        id: json['id'] as String,
        requirementNumber: json['requirement_number'] as int,
        postedBy: json['posted_by'] as String,
        typeOfNurse: json['type_of_nurse'] as String,
        typeOfNurseOther: json['type_of_nurse_other'] as String?,
        frequencyOfCare: json['frequency_of_care'] as String?,
        salaryAmount: json['salary_amount'] as int?,
        scheduleType: json['schedule_type'] as String?,
        startDate: json['start_date'] as String?,
        endDate: json['end_date'] as String?,
        scheduleRepeat: json['schedule_repeat'] as String?,
        specificDays: json['specific_days'] != null
            ? List<int>.from(json['specific_days'] as List)
            : null,
        accommodationProvided: json['accommodation_provided'] as bool,
        foodProvided: json['food_provided'] as bool,
        specialSkills: json['special_skills'] as String?,
        numberOfVacancies: json['number_of_vacancies'] as int,
        preferredGender: json['preferred_gender'] as String?,
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
/// All fields optional/null = no filter applied for that field. `postedBy`
/// is a specific organisation's user id — used by the merged Jobs screen's
/// "View Jobs" redirect from a single Rehab/Hospitals row, not surfaced as
/// its own dropdown (unlike jobs' Job Poster picker).
class OrganisationRequirementListFilters {
  final String? status;
  final String? postedBy;
  final String? organisationType;
  final String? city;
  final String? search;

  const OrganisationRequirementListFilters({
    this.status,
    this.postedBy,
    this.organisationType,
    this.city,
    this.search,
  });

  Map<String, dynamic> toQueryParameters() => {
        'limit': 100,
        if (status != null) 'status': status,
        if (postedBy != null) 'posted_by': postedBy,
        if (organisationType != null) 'organisation_type': organisationType,
        if (city != null) 'city': city,
        if (search != null && search!.isNotEmpty) 'search': search,
      };
}

class AdminOrganisationRequirementsRepository {
  final Dio _dio;

  AdminOrganisationRequirementsRepository(this._dio);

  Future<List<AdminOrganisationRequirement>> list({
    OrganisationRequirementListFilters filters =
        const OrganisationRequirementListFilters(),
  }) async {
    try {
      final res = await _dio.get(
        '/admin/organisation-requirements',
        queryParameters: filters.toQueryParameters(),
      );
      final items = res.data['data'] as List;
      return items
          .map((item) => AdminOrganisationRequirement.fromJson(
              item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Applications here are organisation_requirement_applications rows
  /// (requirement_id, not job_id) — OrganisationRequirementApplicationModel
  /// is the correctly-shaped model for this, NOT JobApplicationModel.
  Future<
      (
        AdminOrganisationRequirement,
        List<OrganisationRequirementApplicationModel>
      )> getDetail(String id) async {
    try {
      final res = await _dio.get('/admin/organisation-requirements/$id');
      final data = res.data['data'] as Map<String, dynamic>;
      final requirement = AdminOrganisationRequirement.fromJson(data);
      final applications = (data['applications'] as List)
          .map((item) => OrganisationRequirementApplicationModel.fromJson(
              item as Map<String, dynamic>))
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
    String? typeOfNurseOther,
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
    required int numberOfVacancies,
    String? preferredGender,
  }) async {
    try {
      await _dio.patch('/admin/organisation-requirements/$id', data: {
        'type_of_nurse': typeOfNurse,
        if (typeOfNurseOther != null && typeOfNurseOther.isNotEmpty) 'type_of_nurse_other': typeOfNurseOther,
        'frequency_of_care': frequencyOfCare,
        'salary_amount': salaryAmount,
        'schedule_type': scheduleType,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        if (scheduleRepeat != null) 'schedule_repeat': scheduleRepeat,
        if (specificDays != null) 'specific_days': specificDays,
        'accommodation_provided': accommodationProvided,
        'food_provided': foodProvided,
        if (specialSkills != null && specialSkills.isNotEmpty)
          'special_skills': specialSkills,
        'number_of_vacancies': numberOfVacancies,
        if (preferredGender != null) 'preferred_gender': preferredGender,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> reject(String id, String reason) async {
    try {
      await _dio.patch('/admin/organisation-requirements/$id/reject',
          data: {'reason': reason});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> decideApplication(
      String requirementId, String applicationId, String status) async {
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
