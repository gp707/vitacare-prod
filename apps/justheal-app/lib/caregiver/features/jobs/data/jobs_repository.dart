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

  /// Every job the caregiver is currently accepted onto or has completed —
  /// a caregiver can hold more than one at once. Needed because
  /// listActiveJobs() only returns active jobs, and an accepted job closes
  /// immediately, so it would otherwise disappear from the caregiver's own
  /// view of it. Durable history — completed jobs stay in the list.
  Future<List<JobModel>> getAssignedJobs() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverJobsAssigned);
      final items = res.data['data'] as List;
      return items.map((item) => JobModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Every application this caregiver has ever made, regardless of the
  /// job's current status — unlike listActiveJobs (active jobs only) and
  /// getAssignedJobs (accepted/completed only), this is the only call that
  /// still returns a rejected/withdrawn application once the underlying
  /// job itself has closed. Used by the Past tab on MyJobs.
  Future<List<JobModel>> getJobHistory() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverJobsHistory);
      final items = res.data['data'] as List;
      return items.map((item) => JobModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Caregiver self-service "I finished this job" — the only way out of
  /// `assigned` now that they may hold several accepted jobs at once.
  /// [closeReason] defaults server-side to CaregiverCloseReason.noReason
  /// when omitted. Returns whether the caregiver is still assigned to any
  /// other job.
  Future<bool> completeJob(String jobId, {String? closeReason}) async {
    try {
      final res = await _dio.post(
        '/caregiver/jobs/$jobId/complete',
        data: {if (closeReason != null) 'close_reason': closeReason},
      );
      return res.data['data']['still_assigned'] as bool;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
