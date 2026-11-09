/// Admin-list tally of a job's / requirement's applicants: how many are
/// waiting, accepted, closed by the caregiver, and rejected — and by whom
/// (the caregiver themselves, or the named patient / organisation / admin).
class ApplicantSummary {
  final int total;
  final int awaiting;
  final int accepted;
  final int completed;
  final int rejectedByCaregiver;
  final List<ApplicantRejecter> rejectedByEmployer;

  const ApplicantSummary({
    required this.total,
    required this.awaiting,
    required this.accepted,
    required this.completed,
    required this.rejectedByCaregiver,
    required this.rejectedByEmployer,
  });

  int get rejected => rejectedByCaregiver + rejectedByEmployer.length;

  factory ApplicantSummary.fromJson(Map<String, dynamic> json) => ApplicantSummary(
        total: json['total'] as int? ?? 0,
        awaiting: json['awaiting'] as int? ?? 0,
        accepted: json['accepted'] as int? ?? 0,
        completed: json['completed'] as int? ?? 0,
        rejectedByCaregiver: json['rejected_by_caregiver'] as int? ?? 0,
        rejectedByEmployer: ((json['rejected_by_employer'] as List?) ?? const [])
            .map((e) => ApplicantRejecter.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ApplicantRejecter {
  final String name;
  final String role;

  const ApplicantRejecter({required this.name, required this.role});

  bool get isAdmin => role == 'admin' || role == 'super_admin';

  factory ApplicantRejecter.fromJson(Map<String, dynamic> json) => ApplicantRejecter(
        name: json['name'] as String? ?? 'Unknown',
        role: json['role'] as String? ?? '',
      );
}
