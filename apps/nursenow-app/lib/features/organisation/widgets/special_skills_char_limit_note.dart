import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Shown directly below the "Job description/Special Skills" field on
/// nursenow-app's Organisation Post/Edit Requirement forms, reacting to its
/// live character count: "N entered · M remaining" while at or under
/// Validation.specialSkillsMaxLength, or a red "N entered · M characters
/// over the limit" once they've typed/pasted past it. The field itself
/// deliberately has no Flutter `maxLength` (which would silently truncate
/// a paste, and can't display an over-limit count at all) — the org can
/// keep typing/pasting past the limit and see exactly how far over they've
/// gone, same convention as Individual's own AreaCharLimitNote.
class SpecialSkillsCharLimitNote extends StatelessWidget {
  final int currentLength;

  const SpecialSkillsCharLimitNote({super.key, required this.currentLength});

  @override
  Widget build(BuildContext context) {
    final limit = Validation.specialSkillsMaxLength;
    final remaining = limit - currentLength;
    final overLimit = remaining < 0;
    final text = overLimit
        ? '$currentLength entered · ${-remaining} character${-remaining == 1 ? '' : 's'} over the $limit character limit'
        : '$currentLength entered · $remaining character${remaining == 1 ? '' : 's'} remaining (max $limit characters)';
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
