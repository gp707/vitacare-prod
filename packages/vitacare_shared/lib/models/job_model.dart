/// Mirrors a row from GET /caregiver/jobs or GET /admin/jobs (SPEC.md 6.6).
/// `myResponse` is only ever populated on the caregiver-facing list (a
/// per-caregiver join); admin-facing responses are fetched separately via
/// the job-detail endpoint's `responses` array (see JobResponseModel).
class JobModel {
  final String id;
  final String workType;
  final String city;
  final String description;
  final String dutyTimings;
  final String language;
  final String genderNeeded;
  final String religion;
  final String status;
  final String postedBy;
  final String createdAt;
  final String? myResponse;

  const JobModel({
    required this.id,
    required this.workType,
    required this.city,
    required this.description,
    required this.dutyTimings,
    required this.language,
    required this.genderNeeded,
    required this.religion,
    required this.status,
    required this.postedBy,
    required this.createdAt,
    this.myResponse,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        workType: json['work_type'] as String,
        city: json['city'] as String,
        description: json['description'] as String,
        dutyTimings: json['duty_timings'] as String,
        language: json['language'] as String,
        genderNeeded: json['gender_needed'] as String,
        religion: json['religion'] as String,
        status: json['status'] as String,
        postedBy: json['posted_by'] as String,
        createdAt: json['created_at'] as String,
        myResponse: json['my_response'] as String?,
      );
}

/// A single caregiver's response to a job, as returned in
/// GET /admin/jobs/:id's `responses` array.
class JobResponseModel {
  final String id;
  final String jobId;
  final String profileId;
  final String response;
  final String? message;
  final String fullName;
  final String phone;
  final String updatedAt;

  const JobResponseModel({
    required this.id,
    required this.jobId,
    required this.profileId,
    required this.response,
    this.message,
    required this.fullName,
    required this.phone,
    required this.updatedAt,
  });

  factory JobResponseModel.fromJson(Map<String, dynamic> json) => JobResponseModel(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        profileId: json['profile_id'] as String,
        response: json['response'] as String,
        message: json['message'] as String?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        updatedAt: json['updated_at'] as String,
      );
}
