import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'applicant_timeline.dart';
import 'call_tap.dart';

/// The accepted caregiver card's green: the Rate Card green (`AppColors.success`) mixed about 36% toward
/// white — a soft, light green with white text on it. It went lighter in steps on request; the lighter it
/// gets the weaker white text reads (about 2.2:1 here), so going further would need dark text instead.
const Color kAcceptedGreen = Color(0xFF5CC583);

/// One accepted caregiver at a glance, on the patient's requirement screen: who they
/// are and what was agreed with them (their own salary and start date). A patient can
/// have several accepted caregivers, each with their own card and their own numbers.
///
/// One button enters the salary and start date (a popup with both fields), or changes them.
///
/// Each card is its own unit: tapping its header folds it down to just the caregiver's name (and
/// back), independent of every other accepted caregiver.
class CaregiverSummaryCard extends StatefulWidget {
  final JobApplicationModel application;
  /// 'daily' or 'monthly' — the job's own frequency, used when no unit was stored.
  final String defaultUnit;
  final bool isDeciding;
  final VoidCallback onAddAgreement;
  final VoidCallback onViewProfile;
  final VoidCallback onReject;

  const CaregiverSummaryCard({
    super.key,
    required this.application,
    required this.defaultUnit,
    required this.isDeciding,
    required this.onAddAgreement,
    required this.onViewProfile,
    required this.onReject,
  });

  @override
  State<CaregiverSummaryCard> createState() => _CaregiverSummaryCardState();
}

class _CaregiverSummaryCardState extends State<CaregiverSummaryCard> {
  /// Open for a newly accepted caregiver (within the last day), while salary or start date is not
  /// entered, and until today is past the agreed start date; otherwise folded. The patient can fold or
  /// unfold any card by tapping its header.
  late bool _expanded = _isNewlyAccepted(widget.application.acceptedAt) ||
      widget.application.agreedSalary == null ||
      widget.application.agreedStartDate == null ||
      !_isPast(widget.application.agreedStartDate);

  /// True once today's date is later than [yyyyMmDd] (the start date itself still counts as "not past").
  static bool _isPast(String? yyyyMmDd) {
    final start = yyyyMmDd == null ? null : DateTime.tryParse(yyyyMmDd);
    if (start == null) return false;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).isAfter(DateTime(start.year, start.month, start.day));
  }

  static bool _isNewlyAccepted(String? acceptedAt) {
    final at = acceptedAt == null ? null : DateTime.tryParse(acceptedAt);
    return at != null && DateTime.now().difference(at) < const Duration(days: 1);
  }

  @override
  Widget build(BuildContext context) {
    final unitWord = (widget.application.agreedSalaryUnit ?? widget.defaultUnit) == 'daily' ? 'day' : 'month';
    final salary = widget.application.agreedSalary;
    final startDate = widget.application.agreedStartDate;
    final hasAgreement = salary != null && startDate != null;

    return Container(
      key: Key('caregiver-card-${widget.application.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        // A solid, slightly lightened green with white text on it.
        color: kAcceptedGreen,
        border: Border.all(color: AppColors.success, width: 1.5),
        borderRadius: BorderRadius.circular(AppSpacing.md),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Who (tap to fold / unfold this caregiver) ──
          InkWell(
            key: Key('caregiver-card-toggle-${widget.application.id}'),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // The name opens the profile; the rest of the header (avatar, chevron) folds the card.
                        Flexible(
                          child: GestureDetector(
                            key: Key('caregiver-name-${widget.application.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onViewProfile,
                            child: Text(
                              widget.application.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTypography.subtitle,
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.check_circle, color: Colors.white, size: 16),
                      ],
                    ),
                    const Text('Accepted', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: AppTypography.small)),
                  ],
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                key: Key('caregiver-card-chevron-${widget.application.id}'),
                color: Colors.white,
                size: 28,
              ),
            ],
          ),
          ),
          if (_expanded) ...[
          const SizedBox(height: AppSpacing.sm),
          PhoneContactRow(phone: widget.application.phone, name: widget.application.fullName, onDark: true),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: Colors.white38),
          const SizedBox(height: AppSpacing.md),

          // ── Their own salary ──
          if (hasAgreement) ...[
            // Label, amount and start date on one line, scaled down a little rather than wrapped.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                key: Key('card-agreement-line-${widget.application.id}'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text('Agreed salary:', style: TextStyle(color: Colors.white70, fontSize: AppTypography.subtitle)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '₹${formatRupees(salary)} per $unitWord',
                    key: Key('card-salary-${widget.application.id}'),
                    softWrap: false,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle, color: Colors.white),
                  ),
                  const Text('  ·  ', style: TextStyle(color: Colors.white70, fontSize: AppTypography.subtitle)),
                  Text(
                    'Starts ${formatLongDate(startDate)}',
                    key: Key('card-start-${widget.application.id}'),
                    softWrap: false,
                    style: const TextStyle(color: Colors.white, fontSize: AppTypography.subtitle),
                  ),
                ],
              ),
            ),
          ] else
            Container(
              key: Key('card-no-salary-${widget.application.id}'),
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
                    key: Key('card-add-agreement-${widget.application.id}'),
                    onPressed: widget.onAddAgreement,
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: const Text('Enter salary and start date'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),

          // ── Actions ──
          if (widget.isDeciding)
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20)),
            )
          else ...[
            if (hasAgreement)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: Key('card-edit-agreement-${widget.application.id}'),
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size.fromHeight(44)),
                    foregroundColor: WidgetStatePropertyAll(Colors.white),
                    side: WidgetStatePropertyAll(BorderSide(color: Colors.white)),
                  ),
                  onPressed: widget.onAddAgreement,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit salary and start date'),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            ApplicantTimeline(widget.application, onDark: true),
            const SizedBox(height: AppSpacing.sm),
            // A Wrap, not a Row: with large text the two buttons drop to separate lines.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onViewProfile,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: WidgetStatePropertyAll(Colors.white),
                    side: WidgetStatePropertyAll(BorderSide(color: Colors.white)),
                  ),
                  icon: const Icon(Icons.person_outline, size: 14),
                  label: const Text('View Profile'),
                ),
                // Rejecting a caregiver who is on the job ends that engagement; it is set
                // apart from the everyday actions, and always asks for a reason first.
                FilledButton.icon(
                  onPressed: widget.onReject,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    // White on red, the counterpart of Accept's white on green — and the one red
                    // action on the green card.
                    backgroundColor: WidgetStateProperty.all(AppColors.error),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                  ),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
        ],
      ),
    );
  }
}
