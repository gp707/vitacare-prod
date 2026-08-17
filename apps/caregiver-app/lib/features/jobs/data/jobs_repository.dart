import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class JobsRepository {
  final Dio _dio;

  JobsRepository(this._dio);

  /// Viewable at any verification status — browsing motivates onboarding;
  /// only applyToJob() is gated server-side.
  Future<List<JobModel>> listActiveJobs() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverJobs, queryParameters: {'limit': 50});
      final items = res.data['data'] as List;
      return items.map((item) => JobModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> applyToJob(String jobId, String status) async {
    try {
      final res = await _dio.post('/caregiver/jobs/$jobId/apply', data: {'status': status});
      return res.data['data']['status'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// The job the caregiver is currently (or was most recently) assigned to
  /// and accepted for — null if they've never been accepted onto a job.
  /// Needed because listActiveJobs() only returns active jobs, and an
  /// accepted job closes immediately, so it would otherwise disappear from
  /// the caregiver's own view of it.
  Future<JobModel?> getAssignedJob() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverJobsAssigned);
      final data = res.data['data'];
      return data == null ? null : JobModel.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
