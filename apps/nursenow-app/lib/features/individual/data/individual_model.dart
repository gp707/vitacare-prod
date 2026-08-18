/// Mirrors GET /individual/me — minimal identity + the job-posting block
/// state (full block is enforced at login, not surfaced here; there's no
/// verification pipeline like a caregiver has).
class IndividualModel {
  final String userId;
  final String fullName;
  final String phone;
  final bool isJobPostingBlocked;

  const IndividualModel({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.isJobPostingBlocked,
  });

  factory IndividualModel.fromJson(Map<String, dynamic> json) => IndividualModel(
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String,
        isJobPostingBlocked: json['is_job_posting_blocked'] as bool,
      );
}
