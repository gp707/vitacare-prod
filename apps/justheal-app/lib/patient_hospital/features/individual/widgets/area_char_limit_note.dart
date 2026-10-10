import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Soft (non-blocking) character guidance for the "Area" field on
/// nursenow-app's Individual Post/Edit Requirement forms — deliberately
/// not a hard Flutter `maxLength` on the field itself, since the whole
/// point is that a patient/family can keep typing past the limit and see
/// exactly how far over they've gone, rather than being silently stopped.
/// Submission itself is not blocked by this — Area only needs to be
/// non-empty to submit, same as before this note was added.
const areaCharLimit = 36;

/// Shown directly below the Area field, reacting to its live character
/// count: "N characters remaining" while at or under the limit, or a red
/// "N characters over the limit" once they've typed past it.
class AreaCharLimitNote extends StatelessWidget {
  final int currentLength;

  const AreaCharLimitNote({super.key, required this.currentLength});

  @override
  Widget build(BuildContext context) {
    final remaining = areaCharLimit - currentLength;
    final overLimit = remaining < 0;
    final text = overLimit
        ? '${-remaining} character${-remaining == 1 ? '' : 's'} over the $areaCharLimit character limit'
        : '$remaining character${remaining == 1 ? '' : 's'} remaining (max $areaCharLimit characters)';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTypography.small,
          color: overLimit ? AppColors.error : AppColors.textSecondary,
          fontWeight: overLimit ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
