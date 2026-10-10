import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// A single resolved display state for a job/requirement card — icon,
/// label, color, and (for the Past tab) a one-line explanation. Every
/// value here is derived from the EXISTING MyApplicationModel fields
/// (status/decidedByAdmin/appliedAt) — see jobCardStatus() below, which is
/// the one place that does this derivation, so every screen reads it the
/// same way rather than re-deriving it ad hoc.
class JobCardStatus {
  final String label;
  final IconData icon;
  final Color color;
  /// Shown on the Past tab under the chip — e.g. "The family chose
  /// another caregiver." Null for Applied/Selected/On duty, which don't
  /// need an explanation (their own stepper/next-step message covers it).
  final String? explanation;

  const JobCardStatus({required this.label, required this.icon, required this.color, this.explanation});
}

/// Mirrors the exact distinctions CLAUDE.md documents for
/// MyApplicationModel — this does not introduce any new status, it only
/// picks a label/icon/color for whichever existing (status,
/// decidedByAdmin, appliedAt) combination applies:
///   applied                                  -> "Applied · Waiting"
///   accepted                                 -> "Selected" (see
///                                                jobStepperStage for the
///                                                Selected/On duty split)
///   completed                                -> "Completed"
///   rejected, appliedAt == null               -> "Not interested" (the
///                                                caregiver declined
///                                                before ever applying —
///                                                see job_applications
///                                                repository's own
///                                                "rejecting directly
///                                                leaves applied_at NULL"
///                                                comment)
///   rejected, appliedAt != null, decided by
///     the caregiver themselves (!decidedByAdmin) -> "Withdrawn by you"
///   rejected, appliedAt != null, decided by
///     the employer (decidedByAdmin)              -> "Not selected"
JobCardStatus jobCardStatus({
  required String status,
  required bool decidedByAdmin,
  required bool hasAppliedAt,
  bool onDuty = false,
}) {
  switch (status) {
    case 'applied':
      return const JobCardStatus(label: 'Applied · Waiting', icon: Icons.hourglass_top, color: AppColors.warning);
    case 'accepted':
      return onDuty
          ? const JobCardStatus(label: 'On duty', icon: Icons.work, color: AppColors.primary)
          : const JobCardStatus(label: 'Selected', icon: Icons.check_circle, color: AppColors.success);
    case 'completed':
      return const JobCardStatus(label: 'Completed', icon: Icons.check_circle, color: AppColors.textSecondary);
    case 'rejected':
      if (!hasAppliedAt) {
        return const JobCardStatus(label: 'Not interested', icon: Icons.not_interested, color: AppColors.textSecondary);
      }
      return decidedByAdmin
          ? const JobCardStatus(
              label: 'Not selected',
              icon: Icons.cancel_outlined,
              color: AppColors.textSecondary,
              explanation: 'They chose another caregiver, or the position was filled.',
            )
          : const JobCardStatus(
              label: 'Withdrawn by you',
              icon: Icons.undo,
              color: AppColors.textSecondary,
              explanation: 'You withdrew your application.',
            );
    default:
      return const JobCardStatus(label: '', icon: Icons.circle, color: AppColors.textSecondary);
  }
}

class JobStatusChip extends StatelessWidget {
  final JobCardStatus status;

  const JobStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 16, color: status.color),
        const SizedBox(width: 4),
        Text(status.label, style: TextStyle(fontWeight: FontWeight.bold, color: status.color)),
      ],
    );
  }
}
