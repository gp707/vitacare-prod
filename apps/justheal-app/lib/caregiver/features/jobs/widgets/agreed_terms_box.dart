import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "Agreed with the family": the salary and start date the patient/family
/// confirmed right after accepting this caregiver. Shown on the Selected card
/// once they have filled it in; nothing is rendered before that.
///
/// [perUnit] is 'day' or 'month' and [startDate] is the API's YYYY-MM-DD date.
/// [leaveDates] and [pauses] are what the family has marked since: leave days
/// are shown as orange day chips and a pause in red, so the caregiver can see
/// exactly which days are unpaid.
class AgreedTermsBox extends StatelessWidget {
  final int salary;
  final String perUnit;
  final String startDate;
  final List<String> leaveDates;
  final List<PausePeriod> pauses;

  const AgreedTermsBox({
    super.key,
    required this.salary,
    required this.perUnit,
    required this.startDate,
    this.leaveDates = const [],
    this.pauses = const [],
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
          Text('Start date: ${formatDate(startDate)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (pauses.isNotEmpty || leaveDates.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _LeaveSection(leaveDates: leaveDates, pauses: pauses),
          ],
        ],
      ),
    );
  }
}

/// What the family marked as unpaid: a pause (open = still paused) and leave days.
class _LeaveSection extends StatelessWidget {
  final List<String> leaveDates;
  final List<PausePeriod> pauses;

  const _LeaveSection({required this.leaveDates, required this.pauses});

  static int _daysBetween(String from, String to) {
    final a = DateTime.tryParse(from);
    final b = DateTime.tryParse(to);
    if (a == null || b == null) return 0;
    return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final open = pauses.where((p) => p.isOpen).toList();
    final closed = pauses.where((p) => !p.isOpen && _daysBetween(p.from, p.to!) > 0).toList();
    return Column(
      key: const Key('leave-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final pause in open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.pause_circle, size: 18, color: Colors.red.shade800),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Salary paused since ${AgreedTermsBox.formatDate(pause.from)}. '
                    'Days until it is resumed count as leave and are not paid.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800),
                  ),
                ),
              ],
            ),
          ),
        for (final pause in closed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Paused ${AgreedTermsBox.formatDate(pause.from)} to ${AgreedTermsBox.formatDate(pause.to!)} '
              '(${_daysBetween(pause.from, pause.to!)} days, not paid)',
              style: TextStyle(color: Colors.deepOrange.shade800, fontWeight: FontWeight.w600),
            ),
          ),
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
