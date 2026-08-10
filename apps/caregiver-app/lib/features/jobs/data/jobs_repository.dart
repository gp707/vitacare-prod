import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class JobsRepository {
  final Dio _dio;

  JobsRepository(this._dio);

  /// Viewable at any verification status (SPEC.md 12 — browsing motivates
  /// onboarding); only respond() is gated server-side.
  Future<List<JobModel>> listActiveJobs() async {
    try {
      final res = await _dio.get(ApiRoutes.caregiverJobs, queryParameters: {'limit': 50});
      final items = res.data['data'] as List;
      return items.map((item) => JobModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<String> respondToJob(String jobId, String response, {String? message}) async {
    try {
      final res = await _dio.post('/caregiver/jobs/$jobId/respond', data: {
        'response': response,
        if (message != null) 'message': message,
      });
      return res.data['data']['response'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
