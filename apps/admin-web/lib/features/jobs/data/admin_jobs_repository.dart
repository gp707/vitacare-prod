import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class CareReceiverInput {
  final String mobility;
  final String communication;
  final String feedingType;
  final bool? tubeFeedingNeedsAssistance;
  final List<String> medicalAssistance;
  final bool hasMedicalCondition;
  final List<String>? medicalConditions;
  final String? medicalInfo;

  const CareReceiverInput({
    required this.mobility,
    required this.communication,
    required this.feedingType,
    this.tubeFeedingNeedsAssistance,
    required this.medicalAssistance,
    required this.hasMedicalCondition,
    this.medicalConditions,
    this.medicalInfo,
  });

  Map<String, dynamic> toJson() => {
        'mobility': mobility,
        'communication': communication,
        'feeding_type': feedingType,
        if (tubeFeedingNeedsAssistance != null)
          'tube_feeding_needs_assistance': tubeFeedingNeedsAssistance,
        'medical_assistance': medicalAssistance,
        'has_medical_condition': hasMedicalCondition,
        if (medicalConditions != null) 'medical_conditions': medicalConditions,
        if (medicalInfo != null && medicalInfo!.isNotEmpty) 'medical_info': medicalInfo,
      };
}

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

  Future<(JobModel, List<JobApplicationModel>)> getDetail(String jobId) async {
    try {
      final res = await _dio.get('/admin/jobs/$jobId');
      final data = res.data['data'] as Map<String, dynamic>;
      final job = JobModel.fromJson(data);
      final applications = (data['applications'] as List)
          .map((item) => JobApplicationModel.fromJson(item as Map<String, dynamic>))
          .toList();
      return (job, applications);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> create({
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    required String description,
    required String dutyType,
    String? startTime,
    String? endTime,
    String? startDate,
    required String language,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    try {
      await _dio.post('/admin/jobs', data: {
        'care_receiver': careReceiver.toJson(),
        'city': city,
        if (area != null && area.isNotEmpty) 'area': area,
        'description': description,
        'duty_type': dutyType,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        if (startDate != null) 'start_date': startDate,
        'language': language,
        if (preferredGender != null) 'preferred_gender': preferredGender,
        if (preferredReligion != null) 'preferred_religion': preferredReligion,
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

  /// Admin decision on a specific applicant — 'accepted' closes the job and
  /// assigns the caregiver; 'rejected' on a previously-accepted application
  /// reopens the job and un-assigns the caregiver; 'rejected' on a still-
  /// applied application just declines it.
  Future<void> decideApplication(String jobId, String applicationId, String status) async {
    try {
      await _dio.patch('/admin/jobs/$jobId/applications/$applicationId', data: {'status': status});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
