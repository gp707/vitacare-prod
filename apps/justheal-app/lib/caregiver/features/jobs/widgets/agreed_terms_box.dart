import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "Agreed with the family": the salary and start date the patient/family
/// confirmed right after accepting this caregiver. Shown on the Selected card
/// once they have filled it in; nothing is rendered before that.
///
/// [perUnit] is 'day' or 'month' and [startDate] is the API's YYYY-MM-DD date.
class AgreedTermsBox extends StatelessWidget {
  final int salary;
  final String perUnit;
  final String startDate;

  /// "Agreed with the family" for a patient's job, "Agreed with the organisation" for an organisation's.
  final String title;

  const AgreedTermsBox({
    super.key,
    required this.salary,
    required this.perUnit,
    required this.startDate,
    this.title = 'Agreed with the family',
  });

  /// "2026-11-20" -> "20 Nov 2026"; falls back to the raw text if it can't be read.
  static String formatDate(String isoDate) => formatLongDate(isoDate);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.success),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handshake_outlined, size: 18, color: AppColors.success),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Salary and start date share one line, so the whole box is two lines at most; the line is
          // scaled down a little rather than ever wrapping onto a third.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              key: const Key('agreed-terms-line'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Salary: ₹${formatRupees(salary)} per $perUnit',
                    softWrap: false, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Text('  ·  ', style: TextStyle(color: AppColors.textSecondary)),
                Text('Start date: ${formatDate(startDate)}',
                    softWrap: false, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
