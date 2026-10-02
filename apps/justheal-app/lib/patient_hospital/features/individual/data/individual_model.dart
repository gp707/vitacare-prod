/// Mirrors GET /individual/me — minimal identity + the job-posting block
/// state (full block is enforced at login, not surfaced here; there's no
/// verification pipeline like a caregiver has).
class IndividualModel {
  final String userId;
  /// Human-friendly sequential id, e.g. 500 — display as "PAT-500" via
  /// patientDisplayId().
  final int? patientNumber;
  final String fullName;
  final String phone;
  final bool isJobPostingBlocked;

  const IndividualModel({
    required this.userId,
    this.patientNumber,
    required this.fullName,
    required this.phone,
    required this.isJobPostingBlocked,
  });

  factory IndividualModel.fromJson(Map<String, dynamic> json) => IndividualModel(
        userId: json['user_id'] as String,
        patientNumber: json['patient_number'] as int?,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        isJobPostingBlocked: json['is_job_posting_blocked'] as bool,
      );
}
