import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// The 4-stage horizontal progress bar shown on an applied/accepted job or
/// requirement card. Purely a client-side visualization over existing
/// data — no new backend status. The 4 stages map onto what already
/// exists:
///   0 Applied   — MyApplicationModel.status == applied
///   1 Selected  — status == accepted, startDate still in the future
///   2 On duty   — status == accepted, startDate has passed (today >= it)
///   3 Completed — status == completed
/// "Selected" vs "On duty" is a pure date comparison the caller makes
/// (see jobStepperStage() below) — there is no distinct backend state for
/// it. Never shown for a rejected/withdrawn application (see the Past tab
/// in jobs_history_screen.dart), which has no meaningful progress to show.
class JobProgressStepper extends StatelessWidget {
  final int currentStage;

  const JobProgressStepper({super.key, required this.currentStage});

  static const _labels = ['Applied', 'Selected', 'On duty', 'Completed'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  color: i <= currentStage ? AppColors.success : AppColors.textSecondary.withValues(alpha: 0.25),
                ),
                const SizedBox(height: 4),
                Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    fontWeight: i == currentStage ? FontWeight.bold : FontWeight.normal,
                    color: i <= currentStage ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Derives the 0-3 stage index for [JobProgressStepper] from an existing
/// MyApplicationModel/startDate pair — the only "decision" here (Selected
/// vs On duty) is a plain date comparison against `DateTime.now()`, not a
/// new piece of server state. Returns null for any status this stepper
/// doesn't apply to (rejected, or no application at all).
int? jobStepperStage({required String applicationStatus, required String? startDate}) {
  switch (applicationStatus) {
    case 'applied':
      return 0;
    case 'accepted':
      final start = startDate == null ? null : DateTime.tryParse(startDate);
      final onDuty = start != null && !start.isAfter(DateTime.now());
      return onDuty ? 2 : 1;
    case 'completed':
      return 3;
    default:
      return null;
  }
}
