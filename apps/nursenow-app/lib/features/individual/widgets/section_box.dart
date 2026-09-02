import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Consistent heading + bordered box wrapper for a form section, used on
/// Post/Edit Requirement so the form reads as clearly separated blocks
/// (Patient Details, Care Preferences, ...) instead of one long list of
/// fields with no visual grouping. The border is deliberately dark/bold
/// (same AppColors.textPrimary + width 2.5 convention as the job/requirement
/// card borders on caregiver-app's Jobs/MyJobs tabs) so the 3 sections read
/// as clearly separated blocks. Every section heading uses the same bold,
/// slightly-larger text style; nothing else on the form should deviate from
/// the default field/label text size — child widgets that need their own
/// standalone group label (e.g. "Toilet Assistance (Mandatory)" above a
/// chip/dropdown group, as opposed to a TextField's own built-in
/// InputDecoration.labelText) should use [fieldGroupLabelStyle] rather than
/// an ad hoc TextStyle, so every such label renders pixel-identical.
class SectionBox extends StatelessWidget {
  static const fieldGroupLabelStyle = TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.w600);

  final IconData icon;
  final String title;
  final List<Widget> children;

  const SectionBox({super.key, required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textPrimary, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(title, style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}
