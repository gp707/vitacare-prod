import 'care_receiver_model.dart';

/// Mirrors a row from GET /caregiver/jobs or GET /admin/jobs.
/// `myApplicationStatus` is only ever populated on the caregiver-facing
/// list (a per-caregiver join); admin-facing applications are fetched
/// separately via the job-detail endpoint's `applications` array (see
/// JobApplicationModel). `careReceiver` is only present on the job-detail
/// response (GET /admin/jobs/:id), not the list endpoints.
class JobModel {
  final String id;
  final String city;
  final String? area;
  final String description;
  final String dutyType;
  final String? startTime;
  final String? endTime;
  final String? startDate;
  final String language;
  final String? preferredGender;
  final String? preferredReligion;
  final String status;
  final String postedBy;
  final String createdAt;
  final String? myApplicationStatus;
  final CareReceiverModel? careReceiver;

  const JobModel({
    required this.id,
    required this.city,
    this.area,
    required this.description,
    required this.dutyType,
    this.startTime,
    this.endTime,
    this.startDate,
    required this.language,
    this.preferredGender,
    this.preferredReligion,
    required this.status,
    required this.postedBy,
    required this.createdAt,
    this.myApplicationStatus,
    this.careReceiver,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        city: json['city'] as String,
        area: json['area'] as String?,
        description: json['description'] as String,
        dutyType: json['duty_type'] as String,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        startDate: json['start_date'] as String?,
        language: json['language'] as String,
        preferredGender: json['preferred_gender'] as String?,
        preferredReligion: json['preferred_religion'] as String?,
        status: json['status'] as String,
        postedBy: json['posted_by'] as String,
        createdAt: json['created_at'] as String,
        myApplicationStatus: json['my_application_status'] as String?,
        careReceiver: json['care_receiver'] == null
            ? null
            : CareReceiverModel.fromJson(json['care_receiver'] as Map<String, dynamic>),
      );
}

/// A single caregiver's application to a job, as returned in
/// GET /admin/jobs/:id's `applications` array.
class JobApplicationModel {
  final String id;
  final String jobId;
  final String profileId;
  final String status;
  final String? decidedBy;
  final String fullName;
  final String phone;
  final String updatedAt;

  const JobApplicationModel({
    required this.id,
    required this.jobId,
    required this.profileId,
    required this.status,
    this.decidedBy,
    required this.fullName,
    required this.phone,
    required this.updatedAt,
  });

  factory JobApplicationModel.fromJson(Map<String, dynamic> json) => JobApplicationModel(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        profileId: json['profile_id'] as String,
        status: json['status'] as String,
        decidedBy: json['decided_by'] as String?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        updatedAt: json['updated_at'] as String,
      );
}
