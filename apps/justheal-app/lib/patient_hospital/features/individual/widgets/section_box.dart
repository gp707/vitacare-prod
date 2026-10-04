import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Consistent heading + bordered box wrapper for a form section, used on
/// Post/Edit Requirement so the form reads as clearly separated blocks
/// (Patient Details, Care Preferences, ...) instead of one long list of
/// fields with no visual grouping. Bold red border on a light green shade —
/// same theme as the job/requirement card borders on caregiver-app's
/// Jobs/MyJobs tabs and nursenow's own Jobs Posted card — so the 3 sections
/// read as clearly separated blocks. Every section heading, and every field
/// group label via [fieldGroupLabelStyle], uses the same bold dark-green
/// text style; nothing else on the form should deviate from the default
/// field/label text size — child widgets that need their own standalone
/// group label (e.g. "Toilet Assistance (Mandatory)" above a chip/dropdown
/// group, as opposed to a TextField's own built-in InputDecoration.labelText)
/// should use [fieldGroupLabelStyle] rather than an ad hoc TextStyle, so
/// every such label renders pixel-identical.
class SectionBox extends StatelessWidget {
  static const fieldGroupLabelStyle =
      TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold, color: AppColors.success);

  final IconData icon;
  final String title;
  final List<Widget> children;

  /// When true, the heading row becomes a tap target that toggles
  /// [expanded] via [onToggle] (owned by the caller, not this widget,
  /// since JobsPostedScreen's mandatory-field validation needs to force a
  /// collapsed section open before it can focus/scroll to a field inside
  /// it — see _RequirementCardState._handleSavePressed). Defaults to
  /// false so every other SectionBox usage (e.g. the Post/Edit
  /// Requirement forms on RegistrationScreen, which are being filled in
  /// for the first time) is unaffected — always expanded, no chevron, no
  /// tap target.
  final bool collapsible;
  final bool expanded;
  final VoidCallback? onToggle;

  const SectionBox({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.collapsible = false,
    this.expanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final showChildren = !collapsible || expanded;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: collapsible ? onToggle : null,
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primaryDark),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: AppTypography.title, fontWeight: FontWeight.bold, color: AppColors.success)),
                ),
                if (collapsible) ...[
                  const Spacer(),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.primaryDark),
                ],
              ],
            ),
          ),
          if (showChildren) ...[
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ],
      ),
    );
  }
}
