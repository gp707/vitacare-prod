import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "Agreed with the family": the salary and start date the patient/family
/// confirmed right after accepting this caregiver. Shown on the Selected card
/// once they have filled it in; nothing is rendered before that.
///
/// [perUnit] is 'day' or 'month' and [startDate] is the API's YYYY-MM-DD date.
/// [leaveDates] are the days the family has marked since, shown as orange day
/// chips so the caregiver can see exactly which days are unpaid.
class AgreedTermsBox extends StatelessWidget {
  final int salary;
  final String perUnit;
  final String startDate;
  final List<String> leaveDates;

  const AgreedTermsBox({
    super.key,
    required this.salary,
    required this.perUnit,
    required this.startDate,
    this.leaveDates = const [],
  });

  /// "2026-11-20" -> "20 Nov 2026"; falls back to the raw text if it can't be read.
  static String formatDate(String isoDate) => formatLongDate(isoDate);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.success),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.handshake_outlined, size: 18, color: AppColors.success),
              SizedBox(width: AppSpacing.xs),
              Text('Agreed with the family', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Salary: ₹${formatRupees(salary)} per $perUnit', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Cycle start date: ${formatDate(startDate)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (leaveDates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _LeaveSection(leaveDates: leaveDates),
          ],
        ],
      ),
    );
  }
}

/// What the family marked as unpaid: leave days.
class _LeaveSection extends StatelessWidget {
  final List<String> leaveDates;

  const _LeaveSection({required this.leaveDates});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('leave-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leaveDates.isNotEmpty) ...[
          Text('On leave (not paid)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange.shade800)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final date in leaveDates)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    border: Border.all(color: Colors.deepOrange.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(formatDayMonth(date), style: TextStyle(color: Colors.deepOrange.shade900, fontSize: AppTypography.small)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
