import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// A deliberately separate section from JobsRepository — organisation
/// openings are NOT merged into the regular Jobs tab (explicit product
/// decision, see "NurseNow" in CLAUDE.md).
class OrganisationOpeningsRepository {
  final Dio _dio;

  OrganisationOpeningsRepository(this._dio);

  Future<List<OrganisationRequirementModel>> listActive() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverOrganisationRequirements);
      final items = res.data['data'] as List;
      return items.map((item) => OrganisationRequirementModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> apply(String requirementId, String status) async {
    try {
      final res = await _dio.post(
        ApiRoutes.caregiverOrganisationRequirementApply(requirementId),
        data: {'status': status},
      );
      return res.data['data']['status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Every organisation requirement the caregiver currently holds or has
  /// completed — same durable-history shape as JobsRepository.getAssignedJobs.
  Future<List<OrganisationRequirementApplicationModel>> getAssigned() async {
    try {
      final res = await _dio.get('${ApiRoutes.caregiverOrganisationRequirements}/assigned');
      final items = res.data['data'] as List;
      return items
          .map((item) => OrganisationRequirementApplicationModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Caregiver self-service "I finished this requirement".
  Future<String> complete(String requirementId) async {
    try {
      final res = await _dio.post('${ApiRoutes.caregiverOrganisationRequirements}/$requirementId/complete');
      return res.data['data']['verification_status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
