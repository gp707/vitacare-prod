import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';
import 'organisation_model.dart';

/// An organisation may post many simultaneous requirements — no
/// one-live-at-a-time limit like Individual. See "NurseNow" in CLAUDE.md.
class OrganisationRepository {
  final Dio _dio;

  OrganisationRepository(this._dio);

  Future<OrganisationModel> getMe() async {
    try {
      final res = await _dio.get(ApiRoutes.organisationMe);
      return OrganisationModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// The "exclusive" org posting form — no About Patient, no city/area/
  /// duty_type (inherited from the org's own registered location), no
  /// frequency_of_care/salary_amount (admin-set on approval).
  Future<OrganisationRequirementModel> createRequirement({
    required String typeOfNurse,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.organisationRequirements, data: {
        'type_of_nurse': typeOfNurse,
        'accommodation_provided': accommodationProvided,
        'food_provided': foodProvided,
        if (specialSkills != null && specialSkills.isNotEmpty) 'special_skills': specialSkills,
      });
      return OrganisationRequirementModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Full requirement history — an org can have many simultaneously, so
  /// unlike Individual this realistically returns more than one/zero.
  Future<List<OrganisationRequirementModel>> listMyRequirements() async {
    try {
      final res = await _dio.get(ApiRoutes.organisationRequirements);
      final items = res.data['data'] as List;
      return items.map((item) => OrganisationRequirementModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<OrganisationRequirementApplicationModel>> listApplications(String requirementId) async {
    try {
      final res = await _dio.get(ApiRoutes.organisationRequirementApplications(requirementId));
      final items = res.data['data'] as List;
      return items
          .map((item) => OrganisationRequirementApplicationModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Full profile of one applicant — same trimmed shape as Individual's
  /// equivalent (see IndividualRepository.getApplicantProfile). Since
  /// Organisation's review is a free list, this can be called for any/
  /// every applicant, not just the one candidate currently under review.
  Future<CaregiverProfileModel> getApplicantProfile(String requirementId, String applicationId) async {
    try {
      final res = await _dio.get(ApiRoutes.organisationRequirementApplicantProfile(requirementId, applicationId));
      return CaregiverProfileModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [status] is 'accepted' or 'rejected' — has the exact same effect as
  /// admin deciding on it. Unlike the individual side, a reason is never
  /// required here (matches admin's own reject flow).
  Future<void> decideApplication(String requirementId, String applicationId, String status) async {
    try {
      await _dio.patch(
        ApiRoutes.organisationRequirementApplicationDecide(requirementId, applicationId),
        data: {'status': status},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> updatePhone(String phone) async {
    try {
      await _dio.patch(ApiRoutes.organisationProfilePhone, data: {'phone': phone});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> updateCode(String code) async {
    try {
      await _dio.patch(ApiRoutes.organisationProfileCode, data: {'code': code});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
