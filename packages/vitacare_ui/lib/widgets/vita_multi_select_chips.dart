import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shared multi-select chip pattern (e.g. languages, service modes) used by
/// both the caregiver registration form and admin edit screens.
class VitaMultiSelectChips extends StatelessWidget {
  final List<String> options;
  final Map<String, String> labels;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const VitaMultiSelectChips({
    super.key,
    required this.options,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(labels[option] ?? option),
          selected: isSelected,
          selectedColor: AppColors.primaryLight,
          checkmarkColor: AppColors.primaryDark,
          onSelected: (nowSelected) {
            final next = List<String>.from(selected);
            if (nowSelected) {
              next.add(option);
            } else {
              next.remove(option);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}
