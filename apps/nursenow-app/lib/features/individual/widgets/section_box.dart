import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Consistent heading + bordered box wrapper for a form section, used on
/// Post/Edit Requirement so the form reads as clearly separated blocks
/// (Patient Details, Care Preferences, ...) instead of one long list of
/// fields with no visual grouping. Every section heading uses the same
/// bold, slightly-larger text style; nothing else on the form should
/// deviate from the default field/label text size.
class SectionBox extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SectionBox({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}
