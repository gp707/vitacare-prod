import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

class CareReceiverInput {
  final int age;
  final String gender;
  final int weightKg;
  final String mobility;
  final String communication;
  final String feedingType;
  final bool? tubeFeedingNeedsAssistance;
  final List<String> medicalAssistance;
  final bool hasMedicalCondition;
  final List<String>? medicalConditions;
  final String? medicalInfo;
  final String toiletAssistance;
  final bool requiresVitalMonitoring;
  final List<String>? vitalMonitoringTypes;

  const CareReceiverInput({
    required this.age,
    required this.gender,
    required this.weightKg,
    required this.mobility,
    required this.communication,
    required this.feedingType,
    this.tubeFeedingNeedsAssistance,
    required this.medicalAssistance,
    required this.hasMedicalCondition,
    this.medicalConditions,
    this.medicalInfo,
    required this.toiletAssistance,
    required this.requiresVitalMonitoring,
    this.vitalMonitoringTypes,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight_kg': weightKg,
        'mobility': mobility,
        'communication': communication,
        'feeding_type': feedingType,
        if (tubeFeedingNeedsAssistance != null)
          'tube_feeding_needs_assistance': tubeFeedingNeedsAssistance,
        'medical_assistance': medicalAssistance,
        'has_medical_condition': hasMedicalCondition,
        if (medicalConditions != null) 'medical_conditions': medicalConditions,
        if (medicalInfo != null && medicalInfo!.isNotEmpty) 'medical_info': medicalInfo,
        'toilet_assistance': toiletAssistance,
        'requires_vital_monitoring': requiresVitalMonitoring,
        if (vitalMonitoringTypes != null) 'vital_monitoring_types': vitalMonitoringTypes,
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

  Map<String, dynamic> _jobPayload({
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    required String description,
    required String dutyType,
    String? startDate,
    required List<String> languages,
    required int salaryMonthly,
    String? preferredGender,
    String? preferredReligion,
  }) =>
      {
        'care_receiver': careReceiver.toJson(),
        'city': city,
        if (area != null && area.isNotEmpty) 'area': area,
        'description': description,
        'duty_type': dutyType,
        if (startDate != null) 'start_date': startDate,
        'languages': languages,
        'salary_monthly': salaryMonthly,
        if (preferredGender != null) 'preferred_gender': preferredGender,
        if (preferredReligion != null) 'preferred_religion': preferredReligion,
      };

  Future<void> create({
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    required String description,
    required String dutyType,
    String? startDate,
    required List<String> languages,
    required int salaryMonthly,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    try {
      await _dio.post(
        '/admin/jobs',
        data: _jobPayload(
          careReceiver: careReceiver,
          city: city,
          area: area,
          description: description,
          dutyType: dutyType,
          startDate: startDate,
          languages: languages,
          salaryMonthly: salaryMonthly,
          preferredGender: preferredGender,
          preferredReligion: preferredReligion,
        ),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Full edit of an existing job (and its care receiver), same job id and
  /// application history. If the job was `closed`, the backend also reposts
  /// it (status flips back to `active`, "New Job" push re-broadcasts).
  Future<void> update(
    String jobId, {
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    required String description,
    required String dutyType,
    String? startDate,
    required List<String> languages,
    required int salaryMonthly,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    try {
      await _dio.patch(
        '/admin/jobs/$jobId',
        data: _jobPayload(
          careReceiver: careReceiver,
          city: city,
          area: area,
          description: description,
          dutyType: dutyType,
          startDate: startDate,
          languages: languages,
          salaryMonthly: salaryMonthly,
          preferredGender: preferredGender,
          preferredReligion: preferredReligion,
        ),
      );
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
