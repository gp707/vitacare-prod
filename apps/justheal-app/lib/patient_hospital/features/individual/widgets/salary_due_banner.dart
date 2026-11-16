import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// One upcoming payment: who/what it is for, and when/how much.
class SalaryDueEntry {
  /// e.g. the job's display id ("PAT-JOB-548") or the caregiver's name.
  final String label;
  final SalaryDue due;
  /// Opens this caregiver's own salary page (agreement, leave days, pause). Null hides
  /// the button.
  final VoidCallback? onOpen;
  const SalaryDueEntry({required this.label, required this.due, this.onOpen});
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
    // The working is done on the days actually worked: leave days earn nothing.
    final rateText = due.unit == 'daily'
        ? '₹${formatRupees(due.rate)}/day × ${due.workedDays} days'
        : '₹${formatRupees(due.rate)}/month × ${due.workedDays} ÷ $salaryMonthDays days';
    final hasLeave = due.leaveDays.isNotEmpty;
    final leaveLabels = due.leaveDays.map((d) => formatDayMonth(toIsoDate(d))).toList();
    final shownLeave = leaveLabels.take(6).join(', ');
    final moreLeave = leaveLabels.length > 6 ? ' +${leaveLabels.length - 6} more' : '';
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
              // The real amount, as the headline figure.
              // A Wrap, not a Row: with large accessibility text "for 2 weeks"
              // drops to the next line instead of overflowing.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: AppSpacing.xs,
                children: [
                  Text('₹${formatRupees(due.amount)}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.2)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(hasLeave ? 'for ${due.workedDays} working days' : 'for 2 weeks',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              // How it was worked out, ending in the same figure.
              Text('$rateText = ₹${formatRupees(due.amount)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
              if (hasLeave)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'On leave (${due.leaveDays.length} of $salaryPeriodDays days): $shownLeave$moreLeave',
                    key: const Key('salary-leave-note'),
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.deepOrange.shade800),
                  ),
                ),
              if (entry.onOpen != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('open-salary'),
                      onPressed: entry.onOpen,
                      style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      label: const Text('Salary & leaves'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
