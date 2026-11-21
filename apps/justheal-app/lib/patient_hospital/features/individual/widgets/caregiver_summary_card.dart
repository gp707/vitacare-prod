import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'applicant_timeline.dart';
import 'call_tap.dart';
import 'feedback_widgets.dart';

/// One accepted caregiver at a glance, on the patient's requirement screen: who they
/// are and what was agreed with them (their own salary and start date). A patient can
/// have several accepted caregivers, each with their own card and their own numbers.
///
/// One button enters the salary and start date (a popup with both fields), or changes them.
class CaregiverSummaryCard extends StatelessWidget {
  final JobApplicationModel application;
  /// 'daily' or 'monthly' — the job's own frequency, used when no unit was stored.
  final String defaultUnit;
  final bool isDeciding;
  final VoidCallback onAddAgreement;
  final VoidCallback onViewProfile;
  final VoidCallback onReject;
  final VoidCallback? onLeaveFeedback;

  const CaregiverSummaryCard({
    super.key,
    required this.application,
    required this.defaultUnit,
    required this.isDeciding,
    required this.onAddAgreement,
    required this.onViewProfile,
    required this.onReject,
    this.onLeaveFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final unitWord = (application.agreedSalaryUnit ?? defaultUnit) == 'daily' ? 'day' : 'month';
    final salary = application.agreedSalary;
    final startDate = application.agreedStartDate;
    final hasAgreement = salary != null && startDate != null;
    final initial = application.fullName.trim().isEmpty ? '?' : application.fullName.trim()[0].toUpperCase();

    return Container(
      key: Key('caregiver-card-${application.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        // The green of the "Accepted" text, as a light tint behind the whole card.
        color: AppColors.success.withValues(alpha: 0.1),
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
              'Starts ${formatLongDate(startDate)}',
              key: Key('card-start-${application.id}'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
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
                    'Agree the salary and start date with this caregiver, then enter them here.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton.icon(
                    key: Key('card-add-agreement-${application.id}'),
                    onPressed: onAddAgreement,
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: const Text('Enter salary and start date'),
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
                child: OutlinedButton.icon(
                  key: Key('card-edit-agreement-${application.id}'),
                  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(44))),
                  onPressed: onAddAgreement,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit salary and start date'),
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
                onEdit: onLeaveFeedback,
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
