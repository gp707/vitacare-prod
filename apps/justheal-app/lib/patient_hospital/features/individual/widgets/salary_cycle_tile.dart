import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// One salary cycle as a record: the period, the status (paid on a date / due /
/// still running), the rate that applied, the leave days inside it, how the amount
/// was worked out, and the amount. A paid cycle shows exactly what it was when it
/// was paid, whatever the rate or leave days are now.
class SalaryCycleTile extends StatelessWidget {
  final SalaryCycleModel cycle;
  /// Shown on a due (ended, unpaid) cycle when given: the family marks it paid.
  final VoidCallback? onMarkPaid;

  const SalaryCycleTile({super.key, required this.cycle, this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = switch (cycle.status) {
      'paid' => ('Paid on ${formatLongDate(cycle.paidOn ?? cycle.cycleEnd)}', AppColors.success),
      'due' => ('Due - not paid yet', Colors.deepOrange.shade800),
      _ => ('Current cycle', AppColors.textSecondary),
    };
    final leave = cycle.leaveDates;
    final shownLeave = leave.take(6).map(formatDayMonth).join(', ');
    final moreLeave = leave.length > 6 ? ' +${leave.length - 6} more' : '';
    return Container(
      key: Key('cycle-${cycle.cycleStart}'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cycle.isPaid ? Colors.green.shade50 : (cycle.isDue ? Colors.amber.shade50 : Colors.white),
        border: Border.all(color: cycle.isPaid ? Colors.green.shade300 : AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatLongDate(cycle.cycleStart)} to ${formatLongDate(cycle.cycleEnd)}',
            key: Key('cycle-period-${cycle.cycleStart}'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(cycle.isPaid ? Icons.check_circle : Icons.schedule, size: 16, color: statusColor),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  statusText,
                  key: Key('cycle-status-${cycle.cycleStart}'),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Rate: \u20b9${formatRupees(cycle.rate)} per ${cycle.unit == 'daily' ? 'day' : 'month'}'),
          Text(
            leave.isEmpty ? 'No leave in this cycle' : 'Leave (${leave.length}): $shownLeave$moreLeave',
            key: Key('cycle-leave-${cycle.cycleStart}'),
            style: TextStyle(color: leave.isEmpty ? AppColors.textSecondary : Colors.deepOrange.shade800),
          ),
          Text(
            cycle.calculation,
            key: Key('cycle-calc-${cycle.cycleStart}'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '\u20b9${formatRupees(cycle.amount)}',
            key: Key('cycle-amount-${cycle.cycleStart}'),
            style: const TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold),
          ),
          if (cycle.isDue && onMarkPaid != null) ...[
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              key: Key('mark-paid-${cycle.cycleStart}'),
              onPressed: onMarkPaid,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Mark as paid'),
            ),
          ],
        ],
      ),
    );
  }
}
