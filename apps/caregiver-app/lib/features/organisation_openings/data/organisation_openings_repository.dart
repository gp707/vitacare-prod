import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// Talks to the organisation-requirements-specific endpoints — the data
/// itself lives in a separate backend table/codepath from regular jobs
/// (see "NurseNow" in CLAUDE.md), but the caregiver-app UI merges both
/// into a single Jobs/MyJobs list (see JobsScreen/MyAssignmentScreen).
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
  /// completed — same durable-history shape as JobsRepository.getAssignedJobs,
  /// and (like that method) returns full requirement records (not bare
  /// application rows) so the merged Jobs/MyJobs screens can render them
  /// with the same card either way.
  Future<List<OrganisationRequirementModel>> getAssigned() async {
    try {
      final res = await _dio.get('${ApiRoutes.caregiverOrganisationRequirements}/assigned');
      final items = res.data['data'] as List;
      return items.map((item) => OrganisationRequirementModel.fromJson(item as Map<String, dynamic>)).toList();
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
