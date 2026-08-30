import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';

/// Only [age]/[gender]/[weightKg] are hard-required — every other field is
/// optional and, if left unselected, is defaulted server-side to a real,
/// explicit value (see CARE_RECEIVER_DEFAULTS in the backend's
/// jobs.service.ts) so the persisted value is never silently null/empty.
class CareReceiverInput {
  final int age;
  final String gender;
  final int weightKg;
  final String? mobility;
  final String? communication;
  final String? feedingType;
  final bool hasMedicalCondition;
  final List<String>? medicalConditions;
  final String? medicalConditionOther;
  final List<String> toiletAssistance;
  final String? toiletAssistanceOther;
  final bool requiresVitalMonitoring;
  final List<String>? vitalMonitoringTypes;

  const CareReceiverInput({
    required this.age,
    required this.gender,
    required this.weightKg,
    this.mobility,
    this.communication,
    this.feedingType,
    required this.hasMedicalCondition,
    this.medicalConditions,
    this.medicalConditionOther,
    required this.toiletAssistance,
    this.toiletAssistanceOther,
    required this.requiresVitalMonitoring,
    this.vitalMonitoringTypes,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight_kg': weightKg,
        if (mobility != null) 'mobility': mobility,
        if (communication != null) 'communication': communication,
        if (feedingType != null) 'feeding_type': feedingType,
        'has_medical_condition': hasMedicalCondition,
        if (medicalConditions != null) 'medical_conditions': medicalConditions,
        if (medicalConditionOther != null && medicalConditionOther!.isNotEmpty)
          'medical_condition_other': medicalConditionOther,
        'toilet_assistance': toiletAssistance,
        if (toiletAssistanceOther != null && toiletAssistanceOther!.isNotEmpty)
          'toilet_assistance_other': toiletAssistanceOther,
        'requires_vital_monitoring': requiresVitalMonitoring,
        if (vitalMonitoringTypes != null)
          'vital_monitoring_types': vitalMonitoringTypes,
      };
}

/// All fields optional/null = no filter applied for that field. `postedBy`
/// is a user id (from [JobPosterOption.id]/the poster dropdown), not a name.
/// `postedByRole` is one level up — filters to every job posted by any user
/// of that role (e.g. 'individual' for the merged Jobs screen's "Patients"
/// poster-type filter), not a specific person.
class JobListFilters {
  final String? postedBy;
  final String? postedByRole;
  final String? city;
  final String? gender;
  final String? dutyType;
  final String? status;
  final String? language;
  final String? search;

  const JobListFilters({
    this.postedBy,
    this.postedByRole,
    this.city,
    this.gender,
    this.dutyType,
    this.status,
    this.language,
    this.search,
  });

  Map<String, dynamic> toQueryParameters() => {
        'limit': 100,
        if (postedBy != null) 'posted_by': postedBy,
        if (postedByRole != null) 'posted_by_role': postedByRole,
        if (city != null) 'city': city,
        if (gender != null) 'gender': gender,
        if (dutyType != null) 'duty_type': dutyType,
        if (status != null) 'status': status,
        if (language != null) 'language': language,
        if (search != null && search!.isNotEmpty) 'search': search,
      };
}

/// An admin who has posted at least one job — powers the "Job Poster" filter
/// dropdown. Shown as name + phone since names can collide.
class JobPosterOption {
  final String id;
  final String fullName;
  final String phone;

  const JobPosterOption(
      {required this.id, required this.fullName, required this.phone});

  factory JobPosterOption.fromJson(Map<String, dynamic> json) =>
      JobPosterOption(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
      );
}

class AdminJobsRepository {
  final Dio _dio;

  AdminJobsRepository(this._dio);

  Future<List<JobModel>> list(
      {JobListFilters filters = const JobListFilters()}) async {
    try {
      final res = await _dio.get('/admin/jobs',
          queryParameters: filters.toQueryParameters());
      final items = res.data['data'] as List;
      return items
          .map((item) => JobModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<JobPosterOption>> listPosters() async {
    try {
      final res = await _dio.get('/admin/jobs/posters');
      final items = res.data['data'] as List;
      return items
          .map((item) => JobPosterOption.fromJson(item as Map<String, dynamic>))
          .toList();
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
          .map((item) =>
              JobApplicationModel.fromJson(item as Map<String, dynamic>))
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
    String? description,
    required String dutyType,
    required String frequencyOfCare,
    String? startDate,
    required List<String> languages,
    required int salaryAmount,
    String? preferredGender,
    String? preferredReligion,
  }) =>
      {
        'care_receiver': careReceiver.toJson(),
        'city': city,
        if (area != null && area.isNotEmpty) 'area': area,
        if (description != null && description.isNotEmpty)
          'description': description,
        'duty_type': dutyType,
        'frequency_of_care': frequencyOfCare,
        if (startDate != null) 'start_date': startDate,
        'languages': languages,
        'salary_amount': salaryAmount,
        if (preferredGender != null) 'preferred_gender': preferredGender,
        if (preferredReligion != null) 'preferred_religion': preferredReligion,
      };

  Future<void> create({
    required CareReceiverInput careReceiver,
    required String city,
    String? area,
    String? description,
    required String dutyType,
    required String frequencyOfCare,
    String? startDate,
    required List<String> languages,
    required int salaryAmount,
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
          frequencyOfCare: frequencyOfCare,
          startDate: startDate,
          languages: languages,
          salaryAmount: salaryAmount,
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
    String? description,
    required String dutyType,
    required String frequencyOfCare,
    String? startDate,
    required List<String> languages,
    required int salaryAmount,
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
          frequencyOfCare: frequencyOfCare,
          startDate: startDate,
          languages: languages,
          salaryAmount: salaryAmount,
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

  /// Only valid from pending_review — declines a NurseNow individual's
  /// requirement, which never goes live. [reason] is shown to the
  /// individual on their own requirement view.
  Future<void> reject(String jobId, String reason) async {
    try {
      await _dio.patch('/admin/jobs/$jobId/reject', data: {'reason': reason});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Admin decision on a specific applicant — 'accepted' closes the job and
  /// assigns the caregiver; 'rejected' on a previously-accepted application
  /// reopens the job and un-assigns the caregiver; 'rejected' on a still-
  /// applied application just declines it.
  Future<void> decideApplication(
      String jobId, String applicationId, String status) async {
    try {
      await _dio.patch('/admin/jobs/$jobId/applications/$applicationId',
          data: {'status': status});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
