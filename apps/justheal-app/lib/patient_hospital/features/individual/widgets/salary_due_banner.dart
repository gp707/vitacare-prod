import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// One upcoming payment: who/what it is for, and when/how much.
class SalaryDueEntry {
  /// e.g. the job's display id ("PAT-JOB-548") or the caregiver's name.
  final String label;
  final SalaryDue due;
  const SalaryDueEntry({required this.label, required this.due});
}

/// "Salary due Fri 4 Dec 2026 (in 18 days)" with the prorated amount for the
/// 2-week period, pinned at the top of the main screen. Salary is paid every 14
/// days counting from the start date, at the agreed per-day or per-month rate
/// (see nextSalaryDue). Renders nothing when there is nothing to show.
class SalaryDueBanner extends StatelessWidget {
  final List<SalaryDueEntry> entries;
  /// The closing line, e.g. who pays whom.
  final String caption;
  /// Show each entry's label (needed when more than one engagement is listed).
  final bool showLabels;
  /// Space around the banner. The default suits a banner pinned above a screen's
  /// content; pass EdgeInsets.zero inside a list that already has its own padding.
  final EdgeInsetsGeometry margin;

  const SalaryDueBanner({
    super.key,
    required this.entries,
    required this.caption,
    this.showLabels = false,
    this.margin = const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
  });

  static const _maxShown = 3;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final sorted = List<SalaryDueEntry>.of(entries)..sort((a, b) => a.due.dueDate.compareTo(b.due.dueDate));
    final shown = sorted.take(_maxShown).toList();
    final hidden = sorted.length - shown.length;
    return Container(
      key: const Key('salary-due-banner'),
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        border: Border.all(color: Colors.amber.shade700),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _EntryLines(entry: shown[i], showLabel: showLabels || sorted.length > 1),
          ],
          if (hidden > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('+ $hidden more', style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
        ],
      ),
    );
  }
}

class _EntryLines extends StatelessWidget {
  final SalaryDueEntry entry;
  final bool showLabel;
  const _EntryLines({required this.entry, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    final due = entry.due;
    final rateText = due.unit == 'daily'
        ? '₹${formatRupees(due.rate)}/day × $salaryPeriodDays days'
        : '₹${formatRupees(due.rate)}/month × $salaryPeriodDays ÷ $salaryMonthDays days';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_available, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Salary due ${formatDueDate(due.dueDate)} (${dueInWords(due.daysLeft)})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLabel) Text(entry.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('₹${formatRupees(due.amount)} for 2 weeks', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(rateText, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
            ],
          ),
        ),
      ],
    );
  }
}
