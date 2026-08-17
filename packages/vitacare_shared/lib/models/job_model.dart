import 'care_receiver_model.dart';

/// The posting admin's contact info — only ever present on
/// GET /caregiver/jobs/assigned, once the caregiver has actually been
/// accepted onto the job. Never present on the browse list.
class JobPosterModel {
  final String fullName;
  final String phone;

  const JobPosterModel({required this.fullName, required this.phone});

  factory JobPosterModel.fromJson(Map<String, dynamic> json) => JobPosterModel(
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
      );
}

/// Mirrors a row from GET /caregiver/jobs or GET /admin/jobs.
/// `myApplicationStatus` is only ever populated on the caregiver-facing
/// list (a per-caregiver join); admin-facing applications are fetched
/// separately via the job-detail endpoint's `applications` array (see
/// JobApplicationModel). `careReceiver` is only present on the job-detail
/// response (GET /admin/jobs/:id), not the list endpoints. `jobPoster` is
/// only present on GET /caregiver/jobs/assigned.
class JobModel {
  final String id;
  final int jobNumber;
  final String city;
  final String? area;
  final String description;
  final String dutyType;
  final String frequencyOfCare;
  final String? startTime;
  final String? endTime;
  final String? startDate;
  final List<String> languages;
  final int? salaryMonthly;
  final String? preferredGender;
  final String? preferredReligion;
  final String status;
  final String postedBy;
  final String postedAt;
  final String createdAt;
  final String? myApplicationStatus;
  final CareReceiverModel? careReceiver;
  final JobPosterModel? jobPoster;

  const JobModel({
    required this.id,
    required this.jobNumber,
    required this.city,
    this.area,
    required this.description,
    required this.dutyType,
    required this.frequencyOfCare,
    this.startTime,
    this.endTime,
    this.startDate,
    required this.languages,
    this.salaryMonthly,
    this.preferredGender,
    this.preferredReligion,
    required this.status,
    required this.postedBy,
    required this.postedAt,
    required this.createdAt,
    this.myApplicationStatus,
    this.careReceiver,
    this.jobPoster,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        jobNumber: json['job_number'] as int,
        city: json['city'] as String,
        area: json['area'] as String?,
        description: json['description'] as String,
        dutyType: json['duty_type'] as String,
        frequencyOfCare: json['frequency_of_care'] as String,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        startDate: json['start_date'] as String?,
        languages: (json['languages'] as List).cast<String>(),
        salaryMonthly: json['salary_monthly'] as int?,
        preferredGender: json['preferred_gender'] as String?,
        preferredReligion: json['preferred_religion'] as String?,
        status: json['status'] as String,
        postedBy: json['posted_by'] as String,
        postedAt: json['posted_at'] as String,
        createdAt: json['created_at'] as String,
        myApplicationStatus: json['my_application_status'] as String?,
        careReceiver: json['care_receiver'] == null
            ? null
            : CareReceiverModel.fromJson(json['care_receiver'] as Map<String, dynamic>),
        jobPoster: json['job_poster'] == null
            ? null
            : JobPosterModel.fromJson(json['job_poster'] as Map<String, dynamic>),
      );

  /// The 3-day "apply by" urgency window, always computed from [postedAt]
  /// (not [createdAt] — a repost restarts this). Purely informational: it
  /// does not block applying, it just drives the caregiver-facing urgency
  /// message.
  DateTime get applyByDate => DateTime.parse(postedAt).add(const Duration(days: 3));

  /// Whole calendar days left until [applyByDate]. 0 means "last day", a
  /// negative number means the window has passed.
  int get daysLeftToApply => applyByDate.difference(DateTime.now()).inDays;
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
