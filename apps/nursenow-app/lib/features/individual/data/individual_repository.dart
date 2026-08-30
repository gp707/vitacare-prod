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
  final String? feedingType;
  final bool hasMedicalCondition;
  final List<String>? medicalConditions;
  final String? medicalConditionOther;
  final List<String>? toiletAssistance;
  final String? toiletAssistanceOther;

  const CareReceiverInput({
    required this.age,
    required this.gender,
    required this.weightKg,
    this.feedingType,
    this.hasMedicalCondition = false,
    this.medicalConditions,
    this.medicalConditionOther,
    this.toiletAssistance,
    this.toiletAssistanceOther,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight_kg': weightKg,
        if (feedingType != null) 'feeding_type': feedingType,
        'has_medical_condition': hasMedicalCondition,
        if (medicalConditions != null) 'medical_conditions': medicalConditions,
        if (medicalConditionOther != null && medicalConditionOther!.isNotEmpty)
          'medical_condition_other': medicalConditionOther,
        if (toiletAssistance != null) 'toilet_assistance': toiletAssistance,
        if (toiletAssistanceOther != null && toiletAssistanceOther!.isNotEmpty)
          'toilet_assistance_other': toiletAssistanceOther,
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

  /// Edits any field of the caller's own requirement in place — allowed
  /// regardless of its current status (pending_review/active/closed), as
  /// long as it has no active (applied/accepted) application (JOB_014
  /// otherwise). No admin re-review is triggered, so this can be called
  /// any number of times. [frequencyOfCare]/[salaryAmount] are only
  /// accepted once admin has approved the requirement at least once
  /// (JOB_013 if sent before that) — omit them entirely while the
  /// requirement is still pending_review, same as at creation.
  Future<JobModel> editRequirement(
    String jobId, {
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    required String startDate,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    String? frequencyOfCare,
    int? salaryAmount,
  }) async {
    try {
      final res = await _dio.patch(ApiRoutes.individualRequirement(jobId), data: {
        'care_receiver': careReceiver.toJson(),
        'city': city,
        'area': area,
        if (description != null && description.isNotEmpty) 'description': description,
        'duty_type': dutyType,
        'start_date': startDate,
        'languages': languages,
        if (preferredGender != null) 'preferred_gender': preferredGender,
        if (preferredReligion != null) 'preferred_religion': preferredReligion,
        if (frequencyOfCare != null) 'frequency_of_care': frequencyOfCare,
        if (salaryAmount != null) 'salary_amount': salaryAmount,
      });
      return JobModel.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Cancels the caller's own requirement — allowed at any point in its
  /// lifecycle (pending_review, active, or already closed by an
  /// acceptance), regardless of whether anyone applied. JOB_015 if it's
  /// already been admin-rejected or cancelled once already. Any still
  /// applied/accepted application is bulk-rejected server-side with a
  /// fixed reason, and an accepted caregiver is flipped back to
  /// available. After this call the individual can no longer see who
  /// applied on this requirement (see listApplications/getApplicantProfile
  /// below), and — since a cancelled requirement no longer counts as
  /// "live" — can immediately post a new one, including a clone of this
  /// one's fields.
  Future<void> cancelRequirement(String jobId) async {
    try {
      await _dio.post(ApiRoutes.individualRequirementCancel(jobId));
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
