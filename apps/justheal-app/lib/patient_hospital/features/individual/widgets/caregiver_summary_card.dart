import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'applicant_timeline.dart';
import 'call_tap.dart';
import 'feedback_widgets.dart';

/// One accepted caregiver at a glance, on the patient's requirement screen: who they
/// are, what was agreed with them (their own salary and start date), the next salary
/// due, and whether they are on leave or paused. A patient can have several accepted
/// caregivers, each with their own card and their own numbers.
///
/// "Salary & leaves" opens that caregiver's own page for the details and changes.
class CaregiverSummaryCard extends StatelessWidget {
  final JobApplicationModel application;
  /// 'daily' or 'monthly' — the job's own frequency, used when no unit was stored.
  final String defaultUnit;
  final bool isDeciding;
  final VoidCallback onOpenSalary;
  final VoidCallback onAddAgreement;
  final VoidCallback onViewProfile;
  final VoidCallback onReject;
  final VoidCallback? onLeaveFeedback;

  const CaregiverSummaryCard({
    super.key,
    required this.application,
    required this.defaultUnit,
    required this.isDeciding,
    required this.onOpenSalary,
    required this.onAddAgreement,
    required this.onViewProfile,
    required this.onReject,
    this.onLeaveFeedback,
  });

  /// The next salary due for this caregiver, or null until their salary is agreed.
  static SalaryDue? dueFor(JobApplicationModel application, String defaultUnit) => nextSalaryDue(
        salary: application.agreedSalary,
        unit: application.agreedSalaryUnit ?? defaultUnit,
        startDate: application.agreedStartDate,
        leaveDates: application.leaveDates,
      );

  @override
  Widget build(BuildContext context) {
    final unitWord = (application.agreedSalaryUnit ?? defaultUnit) == 'daily' ? 'day' : 'month';
    final salary = application.agreedSalary;
    final startDate = application.agreedStartDate;
    final hasAgreement = salary != null && startDate != null;
    final due = dueFor(application, defaultUnit);
    final start = startDate == null ? null : DateTime.tryParse(startDate);
    final now = DateTime.now();
    final started = start != null && !start.isAfter(DateTime(now.year, now.month, now.day));
    final initial = application.fullName.trim().isEmpty ? '?' : application.fullName.trim()[0].toUpperCase();

    return Container(
      key: Key('caregiver-card-${application.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.6), width: 1.5),
        borderRadius: BorderRadius.circular(AppSpacing.md),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Who ──
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryLight,
                child: Text(initial, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.bold, fontSize: AppTypography.title)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            application.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                      ],
                    ),
                    const Text('Accepted', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: AppTypography.small)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PhoneContactRow(phone: application.phone, name: application.fullName),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),

          // ── Their own salary ──
          if (hasAgreement) ...[
            const Text('Agreed salary', style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
            const SizedBox(height: 2),
            Text(
              '₹${formatRupees(salary)} per $unitWord',
              key: Key('card-salary-${application.id}'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.title, color: AppColors.success),
            ),
            Text(
              started ? 'Cycle started ${formatLongDate(startDate)}' : 'Cycle starts ${formatLongDate(startDate)}',
              key: Key('card-start-${application.id}'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (due != null) ...[
              const SizedBox(height: AppSpacing.md),
              _NextSalary(due: due),
            ],
          ] else
            Container(
              key: Key('card-no-salary-${application.id}'),
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade400),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Salary not set yet', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Text(
                    'Agree the salary and cycle start date with this caregiver, then add them here.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton.icon(
                    key: Key('card-add-agreement-${application.id}'),
                    onPressed: onAddAgreement,
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: const Text('Add agreed salary & cycle start date'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),

          // ── Actions ──
          if (isDeciding)
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20)),
            )
          else ...[
            if (hasAgreement)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: Key('open-salary-${application.id}'),
                  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(48))),
                  onPressed: onOpenSalary,
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                  label: const Text('Salary & leaves'),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            ApplicantTimeline(application),
            // Overall feedback about this caregiver, once the work has started.
            if (application.myFeedback != null ||
                application.theirFeedback != null ||
                feedbackEligible(acceptedAt: application.acceptedAt, agreedStartDate: application.agreedStartDate)) ...[
              const SizedBox(height: AppSpacing.sm),
              FeedbackSection(
                aboutLabel: 'caregiver',
                mine: application.myFeedback,
                received: application.theirFeedback,
                eligible: feedbackEligible(acceptedAt: application.acceptedAt, agreedStartDate: application.agreedStartDate),
                onLeave: onLeaveFeedback,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // A Wrap, not a Row: with large text the two buttons drop to separate lines.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: onViewProfile,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.person_outline, size: 14),
                  label: const Text('View Profile'),
                ),
                // Rejecting a caregiver who is on the job ends that engagement; it is set
                // apart from the everyday actions, and always asks for a reason first.
                FilledButton.icon(
                  onPressed: onReject,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: WidgetStateProperty.all(AppColors.error.withValues(alpha: 0.1)),
                    foregroundColor: WidgetStateProperty.all(AppColors.error),
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Next salary · Tue 1 Dec 2026" with the amount for the 2 weeks, how long to go, and
/// any leave or pause that changes it.
class _NextSalary extends StatelessWidget {
  final SalaryDue due;
  const _NextSalary({required this.due});

  @override
  Widget build(BuildContext context) {
    final hasLeave = due.leaveDays.isNotEmpty;
    return Container(
      key: const Key('next-salary'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text('Next salary · ${formatDueDate(due.dueDate)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpacing.xs,
            children: [
              Text(
                '₹${formatRupees(due.amount)}',
                key: const Key('next-salary-amount'),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.2),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${dueInWords(due.daysLeft)}${hasLeave ? ' · ${due.workedDays} working days' : ''}',
                  key: const Key('next-salary-when'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (hasLeave) ...[
            const SizedBox(height: AppSpacing.xs),
            _Tag(
              key: const Key('card-leave-tag'),
              icon: Icons.event_busy_outlined,
              text: due.leaveDays.length == 1 ? '1 day on leave this period' : '${due.leaveDays.length} days on leave this period',
              color: Colors.deepOrange.shade800,
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Tag({super.key, required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: AppTypography.small))),
      ],
    );
  }
}
