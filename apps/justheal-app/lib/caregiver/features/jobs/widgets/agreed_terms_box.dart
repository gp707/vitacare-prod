import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "Agreed with the family": the salary and start date the patient/family
/// confirmed right after accepting this caregiver. Shown on the Selected card
/// once they have filled it in; nothing is rendered before that.
///
/// [perUnit] is 'day' or 'month' (the job's own frequency of care) and
/// [startDate] is the API's YYYY-MM-DD date.
class AgreedTermsBox extends StatelessWidget {
  final int salary;
  final String perUnit;
  final String startDate;

  const AgreedTermsBox({super.key, required this.salary, required this.perUnit, required this.startDate});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "2026-11-20" -> "20 Nov 2026"; falls back to the raw text if it can't be read.
  static String formatDate(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    return '${parsed.day} ${_months[parsed.month - 1]} ${parsed.year}';
  }

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
          Text('Salary: ₹$salary per $perUnit', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Start date: ${formatDate(startDate)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
