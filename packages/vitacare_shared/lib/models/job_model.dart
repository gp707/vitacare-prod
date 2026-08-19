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

/// The caregiver's own application to this job, if any, with the real
/// per-transition timeline — not just the current status — so the UI can
/// show what actually happened and when, e.g. "Applied: ... / Accepted:
/// ... / Declined by employer: ..." instead of a bare "You declined" that
/// can't tell a self-decline apart from an admin undoing a prior
/// acceptance. [decidedByAdmin] is true whenever an admin (not the
/// caregiver themselves) made the current status happen — covers both
/// "admin rejected a still-applied application" and "admin undid a prior
/// acceptance"; both read to the caregiver as "declined by the employer".
class MyApplicationModel {
  final String status;
  final String? appliedAt;
  final String? acceptedAt;
  final String? rejectedAt;
  final String? completedAt;
  final bool decidedByAdmin;

  const MyApplicationModel({
    required this.status,
    this.appliedAt,
    this.acceptedAt,
    this.rejectedAt,
    this.completedAt,
    required this.decidedByAdmin,
  });

  factory MyApplicationModel.fromJson(Map<String, dynamic> json) => MyApplicationModel(
        status: json['status'] as String,
        appliedAt: json['applied_at'] as String?,
        acceptedAt: json['accepted_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        completedAt: json['completed_at'] as String?,
        decidedByAdmin: json['decided_by_admin'] as bool,
      );
}

/// Mirrors a row from GET /caregiver/jobs or GET /admin/jobs.
/// `myApplication` is only ever populated on the caregiver-facing list (a
/// per-caregiver join); admin-facing applications are fetched separately
/// via the job-detail endpoint's `applications` array (see
/// JobApplicationModel). `careReceiver` is only present on the job-detail
/// response (GET /admin/jobs/:id), not the list endpoints. `jobPoster` is
/// only present on GET /caregiver/jobs/assigned.
class JobModel {
  final String id;
  /// Internal only — no longer displayed; use [jobDisplayId] instead.
  final int jobNumber;
  /// Set only when this job was posted by an admin — backs the
  /// "ADMIN-JOB-<n>" display id (migration 047, starts at 500). Exactly
  /// one of [adminJobNumber]/[patientJobNumber] is non-null; use
  /// [jobDisplayId] rather than reading these directly.
  final int? adminJobNumber;
  /// Set only when this job was posted by a NurseNow individual — backs
  /// the "PAT-JOB-<n>" display id (migration 047, starts at 500).
  final int? patientJobNumber;
  final String city;
  final String? area;
  final String? description;
  final String dutyType;
  /// Null only for a NurseNow individual-posted job still in
  /// pending_review — an admin sets it (along with [salaryAmount]) on
  /// approval. Always non-null for an admin-posted or already-approved job.
  final String? frequencyOfCare;
  final String? startTime;
  final String? endTime;
  final String? startDate;
  final List<String> languages;
  final int? salaryAmount;
  final String? preferredGender;
  final String? preferredReligion;
  final String status;
  final String postedBy;
  final String postedAt;
  final String createdAt;
  final MyApplicationModel? myApplication;
  final CareReceiverModel? careReceiver;
  final JobPosterModel? jobPoster;
  /// Only set when an admin rejects a pending_review job — null otherwise,
  /// including for a normal close.
  final String? rejectionReason;
  /// Only present on admin-facing responses (via a users join) — the
  /// poster's role/name, e.g. 'individual' for a NurseNow patient/family
  /// posting vs 'admin'/'super_admin' for admin's own. Null on
  /// caregiver-facing responses.
  final String? postedByRole;
  final String? postedByName;

  const JobModel({
    required this.id,
    required this.jobNumber,
    this.adminJobNumber,
    this.patientJobNumber,
    required this.city,
    this.area,
    this.description,
    required this.dutyType,
    this.frequencyOfCare,
    this.startTime,
    this.endTime,
    this.startDate,
    required this.languages,
    this.salaryAmount,
    this.preferredGender,
    this.preferredReligion,
    required this.status,
    required this.postedBy,
    required this.postedAt,
    required this.createdAt,
    this.myApplication,
    this.careReceiver,
    this.jobPoster,
    this.rejectionReason,
    this.postedByRole,
    this.postedByName,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        jobNumber: json['job_number'] as int,
        adminJobNumber: json['admin_job_number'] as int?,
        patientJobNumber: json['patient_job_number'] as int?,
        city: json['city'] as String,
        area: json['area'] as String?,
        description: json['description'] as String?,
        dutyType: json['duty_type'] as String,
        frequencyOfCare: json['frequency_of_care'] as String?,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        startDate: json['start_date'] as String?,
        languages: (json['languages'] as List).cast<String>(),
        salaryAmount: json['salary_amount'] as int?,
        preferredGender: json['preferred_gender'] as String?,
        preferredReligion: json['preferred_religion'] as String?,
        status: json['status'] as String,
        postedBy: json['posted_by'] as String,
        postedAt: json['posted_at'] as String,
        createdAt: json['created_at'] as String,
        myApplication: json['my_application'] == null
            ? null
            : MyApplicationModel.fromJson(json['my_application'] as Map<String, dynamic>),
        careReceiver: json['care_receiver'] == null
            ? null
            : CareReceiverModel.fromJson(json['care_receiver'] as Map<String, dynamic>),
        jobPoster: json['job_poster'] == null
            ? null
            : JobPosterModel.fromJson(json['job_poster'] as Map<String, dynamic>),
        rejectionReason: json['rejection_reason'] as String?,
        postedByRole: json['posted_by_role'] as String?,
        postedByName: json['posted_by_name'] as String?,
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

/// Human-friendly display id for a job — "ADMIN-JOB-<n>" or "PAT-JOB-<n>"
/// depending on which of [JobModel.adminJobNumber]/[JobModel.patientJobNumber]
/// is set, replacing the old generic "Job #<n>" label everywhere (kept
/// here, not duplicated per app, so admin-web/caregiver-app/nursenow-app
/// all render identical text — same convention as [organisationScheduleLabel]).
String jobDisplayId(JobModel job) {
  if (job.adminJobNumber != null) return 'ADMIN-JOB-${job.adminJobNumber}';
  if (job.patientJobNumber != null) return 'PAT-JOB-${job.patientJobNumber}';
  return 'JOB-${job.jobNumber}';
}

/// A single caregiver's application to a job, as returned in
/// GET /admin/jobs/:id's `applications` array.
class JobApplicationModel {
  final String id;
  final String jobId;
  final String profileId;
  final String status;
  final String? decidedBy;
  final String? decidedByName;
  final String fullName;
  final String phone;
  final String? appliedAt;
  final String? acceptedAt;
  final String? rejectedAt;
  final String? declineReason;
  final String updatedAt;

  const JobApplicationModel({
    required this.id,
    required this.jobId,
    required this.profileId,
    required this.status,
    this.decidedBy,
    this.decidedByName,
    required this.fullName,
    required this.phone,
    this.appliedAt,
    this.acceptedAt,
    this.rejectedAt,
    this.declineReason,
    required this.updatedAt,
  });

  factory JobApplicationModel.fromJson(Map<String, dynamic> json) => JobApplicationModel(
        id: json['id'] as String,
        jobId: json['job_id'] as String,
        profileId: json['profile_id'] as String,
        status: json['status'] as String,
        decidedBy: json['decided_by'] as String?,
        decidedByName: json['decided_by_name'] as String?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        appliedAt: json['applied_at'] as String?,
        acceptedAt: json['accepted_at'] as String?,
        rejectedAt: json['rejected_at'] as String?,
        declineReason: json['decline_reason'] as String?,
        updatedAt: json['updated_at'] as String,
      );
}
