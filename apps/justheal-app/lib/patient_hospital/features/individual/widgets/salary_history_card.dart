import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'salary_cycle_tile.dart';

/// The cycle-by-cycle salary record of one caregiver (newest first): paid cycles
/// frozen as they were, due cycles with a "Mark as paid" button, and the running
/// cycle with its current rate. [onMarkPaid] is null on a read-only (past) record.
class SalaryHistoryCard extends StatelessWidget {
  final List<SalaryCycleModel> cycles;
  final void Function(SalaryCycleModel cycle)? onMarkPaid;

  const SalaryHistoryCard({super.key, required this.cycles, this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('salary-history'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history, size: 20, color: AppColors.primary),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text('Salary history', style: TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Each 14-day cycle is kept here with its rate and leave days. When you pay a cycle, mark it as paid: the caregiver is told.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
          ),
          if (cycles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'No salary cycles yet. The first one ends 14 days after the cycle start date.',
                key: Key('no-cycles'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final cycle in cycles) ...[
            const SizedBox(height: AppSpacing.sm),
            SalaryCycleTile(
              cycle: cycle,
              onMarkPaid: onMarkPaid == null ? null : () => onMarkPaid!(cycle),
            ),
          ],
        ],
      ),
    );
  }
}
