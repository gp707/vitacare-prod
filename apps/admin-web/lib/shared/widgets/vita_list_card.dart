import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Mobile-friendly fallback for a `DataTable` row, shown below the mobile
/// breakpoint (`context.isMobile`) instead of the table — a `DataTable`
/// only ever gets *narrower* via horizontal scroll, never restacks its
/// columns, which is a poor fit for a phone screen. Every field/action a
/// `DataRow` would have shown as a column is instead stacked vertically
/// here. Each of the 4 `DataTable`-based list screens (Caregivers,
/// Patients/Family, Rehab/Hospitals, Audit Logs) renders one of these per
/// item on mobile, alongside its existing `DataTable` for wider screens —
/// same data, same callbacks, just a different container.
class VitaListCard extends StatelessWidget {
  final Widget title;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Each entry is one row of detail — usually built via [VitaListCard.kv]
  /// for a simple "label: value" line, but any widget works (e.g. audit
  /// logs' job/target cells, which are themselves multi-line composites).
  final List<Widget> fields;

  final List<Widget> actions;

  const VitaListCard({
    super.key,
    required this.title,
    this.trailing,
    this.onTap,
    this.fields = const [],
    this.actions = const [],
  });

  /// A simple "label: value" detail line — the common case for [fields].
  static Widget kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
            TextSpan(text: value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      child: title,
                    ),
                  ),
                  // Flexible (not a bare child) so a longer-than-expected
                  // trailing widget (e.g. a block reason) shrinks/wraps
                  // instead of forcing a RenderFlex overflow.
                  if (trailing != null) Flexible(child: trailing!),
                ],
              ),
              ...fields,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
