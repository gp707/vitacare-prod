import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// The salary figure — always the most important number on a job/
/// requirement card, so it gets its own green banner with a rupee icon
/// rather than reading as just another line of text. Same visual language
/// as caregiver-app's own SalaryBadge (job_detail_card.dart) — duplicated
/// here rather than shared, same precedent as RateCardButton/
/// WhatsAppHelpButton (see CLAUDE.md).
class SalaryBadge extends StatelessWidget {
  final String amount;
  final String? frequencyOfCare;

  const SalaryBadge({super.key, required this.amount, required this.frequencyOfCare});

  @override
  Widget build(BuildContext context) {
    final unit = frequencyOfCare == 'daily' ? 'day' : 'month';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.success),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            child: const Icon(Icons.currency_rupee, size: 12, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              '$amount/$unit',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold, color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single at-a-glance fact (duty hours, location, ...) paired with a fixed
/// icon rather than relying on the reader parsing an English label — the
/// icon marks the category, the text still carries the actual value. Same
/// visual language as caregiver-app's own IconField.
class IconField extends StatelessWidget {
  final IconData icon;
  final String text;
  // Null means "wrap freely, no line cap" — used for fields whose value can
  // be a long comma-joined list (e.g. multiple medical conditions) where
  // truncating to one ellipsized line would hide information the patient
  // actually needs to see at a glance.
  final int? maxLines;

  const IconField({super.key, required this.icon, required this.text, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 13, color: AppColors.primaryDark),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.bold, color: AppColors.success),
            maxLines: maxLines,
            overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
