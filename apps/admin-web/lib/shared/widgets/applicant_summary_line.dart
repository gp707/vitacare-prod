import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "3 applicants · 1 accepted · 2 rejected (Super Admin (admin), Hansa)" —
/// shown next to a job's / requirement's Applicants button so admin sees the
/// outcome without opening the dialog. Rejections name who did it: the
/// deciding patient / organisation / admin, or "caregiver" for a decline.
class ApplicantSummaryLine extends StatelessWidget {
  final ApplicantSummary? summary;

  const ApplicantSummaryLine({super.key, required this.summary});

  /// "Hansa, Super Admin (admin) x2, caregiver" — repeated names collapse to a count.
  static String rejecters(ApplicantSummary s) {
    final counts = <String, int>{};
    for (final r in s.rejectedByEmployer) {
      final label = r.isAdmin ? '${r.name} (admin)' : r.name;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (s.rejectedByCaregiver > 0) counts['caregiver'] = s.rejectedByCaregiver;
    return counts.entries.map((e) => e.value > 1 ? '${e.key} x${e.value}' : e.key).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const SizedBox.shrink();
    const base = TextStyle(fontSize: AppTypography.small, color: AppColors.textSecondary);
    if (s.total == 0) return const Text('0 applicants', style: base);
    final parts = <InlineSpan>[
      TextSpan(text: '${s.total} applicant${s.total == 1 ? '' : 's'}'),
      if (s.awaiting > 0) TextSpan(text: ' · ${s.awaiting} awaiting'),
      if (s.accepted > 0)
        TextSpan(
          text: ' · ${s.accepted} accepted',
          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
        ),
      if (s.completed > 0) TextSpan(text: ' · ${s.completed} closed by caregiver'),
      if (s.rejected > 0)
        TextSpan(
          text: ' · ${s.rejected} rejected (${rejecters(s)})',
          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
        ),
    ];
    return Text.rich(TextSpan(style: base, children: parts));
  }
}
