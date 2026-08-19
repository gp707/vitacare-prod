import 'package:dio/dio.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import '../../../core/network/api_exception.dart';
import 'individual_model.dart';

/// Same shape as admin-web's CareReceiverInput (About Patient section) —
/// only age/gender/weight_kg are required, every other field defaults
/// server-side (CARE_RECEIVER_DEFAULTS in jobs.service.ts) when omitted.
class CareReceiverInput {
  final int age;
  final String gender;
  final int weightKg;
  final String? mobility;
  final String? communication;
  final String? feedingType;
  final List<String>? medicalAssistance;
  final bool hasMedicalCondition;
  final List<String>? medicalConditions;
  final String? medicalConditionOther;
  final List<String>? toiletAssistance;
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
    this.medicalAssistance,
    this.hasMedicalCondition = false,
    this.medicalConditions,
    this.medicalConditionOther,
    this.toiletAssistance,
    this.toiletAssistanceOther,
    this.requiresVitalMonitoring = false,
    this.vitalMonitoringTypes,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight_kg': weightKg,
        if (mobility != null) 'mobility': mobility,
        if (communication != null) 'communication': communication,
        if (feedingType != null) 'feeding_type': feedingType,
        if (medicalAssistance != null) 'medical_assistance': medicalAssistance,
        'has_medical_condition': hasMedicalCondition,
        if (medicalConditions != null) 'medical_conditions': medicalConditions,
        if (medicalConditionOther != null && medicalConditionOther!.isNotEmpty)
          'medical_condition_other': medicalConditionOther,
        if (toiletAssistance != null) 'toilet_assistance': toiletAssistance,
        if (toiletAssistanceOther != null && toiletAssistanceOther!.isNotEmpty)
          'toilet_assistance_other': toiletAssistanceOther,
        'requires_vital_monitoring': requiresVitalMonitoring,
        if (vitalMonitoringTypes != null) 'vital_monitoring_types': vitalMonitoringTypes,
      };
}

class IndividualRepository {
  final Dio _dio;

  IndividualRepository(this._dio);

  Future<IndividualModel> getMe() async {
    try {
      final res = await _dio.get(ApiRoutes.individualMe);
      return IndividualModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Creates a pending_review requirement — frequency_of_care/salary_amount
  /// are not collected here; an admin sets them on approval. One live
  /// requirement (pending_review or active) at a time — a second attempt
  /// while one is already in flight is rejected server-side (JOB_009).
  Future<JobModel> createRequirement({
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    required String startDate,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
  }) async {
    try {
      final res = await _dio.post(ApiRoutes.individualRequirements, data: {
        'care_receiver': careReceiver.toJson(),
        'city': city,
        'area': area,
        if (description != null && description.isNotEmpty) 'description': description,
        'duty_type': dutyType,
        'start_date': startDate,
        'languages': languages,
        if (preferredGender != null) 'preferred_gender': preferredGender,
        if (preferredReligion != null) 'preferred_religion': preferredReligion,
      });
      return JobModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// In practice zero-or-one given the one-live-requirement rule, but
  /// shaped as a list for durable history (a closed/rejected/completed
  /// requirement stays visible instead of disappearing).
  Future<List<JobModel>> listMyRequirements() async {
    try {
      final res = await _dio.get(ApiRoutes.individualRequirements);
      final items = res.data['data'] as List;
      return items.map((item) => JobModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<JobApplicationModel>> listApplications(String jobId) async {
    try {
      final res = await _dio.get(ApiRoutes.individualRequirementApplications(jobId));
      final items = res.data['data'] as List;
      return items.map((item) => JobApplicationModel.fromJson(item as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Full profile of one applicant — same deliberately-trimmed shape as a
  /// caregiver's own self-view minus email/document URLs/job-search
  /// preferences (see CaregiverService.getApplicantProfile server-side).
  /// Ownership-checked server-side: only viewable if this application
  /// actually belongs to a requirement the caller posted.
  Future<CaregiverProfileModel> getApplicantProfile(String jobId, String applicationId) async {
    try {
      final res = await _dio.get(ApiRoutes.individualRequirementApplicantProfile(jobId, applicationId));
      return CaregiverProfileModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// [status] is 'accepted' or 'rejected' — has the exact same effect as
  /// admin deciding on it (closes the job, flips the caregiver to
  /// assigned/available). [reason] is required server-side (JOB_012) when
  /// rejecting — the one-at-a-time candidate review flow always supplies
  /// one before calling this for a reject.
  Future<void> decideApplication(String jobId, String applicationId, String status, {String? reason}) async {
    try {
      await _dio.patch(
        ApiRoutes.individualRequirementApplicationDecide(jobId, applicationId),
        data: {
          'status': status,
          if (reason != null) 'reason': reason,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// No re-review/verification pipeline to trigger, unlike caregiver-app's
  /// equivalent — an individual account has none.
  Future<void> updatePhone(String phone) async {
    try {
      await _dio.patch(ApiRoutes.individualProfilePhone, data: {'phone': phone});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> updateCode(String code) async {
    try {
      await _dio.patch(ApiRoutes.individualProfileCode, data: {'code': code});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
