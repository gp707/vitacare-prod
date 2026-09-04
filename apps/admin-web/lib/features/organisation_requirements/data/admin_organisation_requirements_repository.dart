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
  final bool accommodationProvided;
  final bool foodProvided;
  final String? specialSkills;
  /// Org-set at creation, 1-49, defaults to 1 — how many caregivers this
  /// one requirement is looking to fill. Org-owned, same as above.
  final int numberOfVacancies;
  /// Org-set at creation. Null = no preference. Org-owned, same as above.
  final String? preferredGender;
  /// Org-set at creation — 'short_term' or 'long_term'. Org-owned, same as
  /// above; admin never sets or edits this.
  final String? durationType;
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
    required this.accommodationProvided,
    required this.foodProvided,
    this.specialSkills,
    required this.numberOfVacancies,
    this.preferredGender,
    this.durationType,
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
        accommodationProvided: json['accommodation_provided'] as bool,
        foodProvided: json['food_provided'] as bool,
        specialSkills: json['special_skills'] as String?,
        numberOfVacancies: json['number_of_vacancies'] as int,
        preferredGender: json['preferred_gender'] as String?,
        durationType: json['duration_type'] as String?,
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

  /// Approves a pending_review requirement — a bare click, no body. The
  /// organisation set every field on the requirement itself; admin owns
  /// none of them (see "NurseNow" in CLAUDE.md).
  Future<void> approve(String id) async {
    try {
      await _dio.patch('/admin/organisation-requirements/$id');
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
