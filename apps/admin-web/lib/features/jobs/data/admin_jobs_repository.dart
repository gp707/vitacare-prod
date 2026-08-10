import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class AdminJobsRepository {
  final Dio _dio;

  AdminJobsRepository(this._dio);

  Future<List<JobModel>> list({String? status}) async {
    try {
      final res = await _dio.get('/admin/jobs', queryParameters: {
        'limit': 100,
        if (status != null) 'status': status,
      });
      final items = res.data['data'] as List;
      return items.map((item) => JobModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<(JobModel, List<JobResponseModel>)> getDetail(String jobId) async {
    try {
      final res = await _dio.get('/admin/jobs/$jobId');
      final data = res.data['data'] as Map<String, dynamic>;
      final job = JobModel.fromJson(data);
      final responses = (data['responses'] as List)
          .map((item) => JobResponseModel.fromJson(item as Map<String, dynamic>))
          .toList();
      return (job, responses);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> create({
    required String workType,
    required String city,
    required String description,
    required String dutyTimings,
    required String language,
    required String genderNeeded,
    required String religion,
  }) async {
    try {
      await _dio.post('/admin/jobs', data: {
        'work_type': workType,
        'city': city,
        'description': description,
        'duty_timings': dutyTimings,
        'language': language,
        'gender_needed': genderNeeded,
        'religion': religion,
      });
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> close(String jobId) async {
    try {
      await _dio.patch('/admin/jobs/$jobId/close');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> remind(String jobId) async {
    try {
      await _dio.post('/admin/jobs/$jobId/remind');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
