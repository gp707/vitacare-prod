import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

String formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Purely informational urgency message — never blocks applying, even once
/// the 3-day window has passed.
String urgencyLabel(int daysLeft) {
  if (daysLeft <= 0) return 'Application window closed';
  if (daysLeft == 1) return '1 day left to apply';
  return '$daysLeft days left to apply';
}

Color urgencyColor(int daysLeft) {
  if (daysLeft <= 0) return AppColors.error;
  if (daysLeft == 1) return AppColors.warning;
  return AppColors.success;
}

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
    );
  }
}

class Tag extends StatelessWidget {
  final String label;

  const Tag(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Job header (Job #, urgency, salary), the About Patient / About Patient
/// Condition / About Nurse-Caregiver Requirement sections, and the
/// free-text description — everything about a job except caregiver-action
/// controls. Shared between the Jobs list card (which appends Apply/Reject)
/// and the MyJobs tab (which appends an "Accepted" status
/// instead), so the same care-needs picture renders identically wherever a
/// caregiver sees a job.
class JobDetailCard extends StatelessWidget {
  final JobModel job;

  const JobDetailCard({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Job #${job.jobNumber}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                urgencyLabel(job.daysLeftToApply),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: urgencyColor(job.daysLeftToApply),
                ),
              ),
            ),
          ],
        ),
        if (job.salaryMonthly != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              border: Border.all(color: AppColors.success),
            ),
            child: Text(
              '₹${job.salaryMonthly}/month',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${DutyType.displayNames[job.dutyType] ?? job.dutyType} in '
          '${City.displayNames[job.city] ?? job.city}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'Posted: ${formatDate(DateTime.parse(job.postedAt))}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (job.careReceiver != null) ...[
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          const SectionLabel('About Patient'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            children: [
              Tag('${job.careReceiver!.age} yrs'),
              Tag(capitalize(job.careReceiver!.gender)),
              Tag('${job.careReceiver!.weightKg} kg'),
              Tag(Mobility.displayNames[job.careReceiver!.mobility] ?? job.careReceiver!.mobility),
              Tag(Communication.displayNames[job.careReceiver!.communication] ??
                  job.careReceiver!.communication),
              Tag(FeedingType.displayNames[job.careReceiver!.feedingType] ?? job.careReceiver!.feedingType),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const SectionLabel('About Patient Condition'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            children: [
              for (final m in job.careReceiver!.medicalAssistance)
                Tag(MedicalAssistance.displayNames[m] ?? m),
              for (final t in job.careReceiver!.toiletAssistance)
                Tag('Toilet: ${ToiletAssistance.displayNames[t] ?? t}'),
              if (job.careReceiver!.hasMedicalCondition)
                for (final c in job.careReceiver!.medicalConditions)
                  Tag(MedicalCondition.displayNames[c] ?? c),
              if (job.careReceiver!.requiresVitalMonitoring)
                for (final v in job.careReceiver!.vitalMonitoringTypes)
                  Tag('Monitor: ${VitalMonitoringType.displayNames[v] ?? v}'),
            ],
          ),
          if (job.careReceiver!.medicalInfo != null && job.careReceiver!.medicalInfo!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              job.careReceiver!.medicalInfo!,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        const SectionLabel('About Nurse/Caregiver Requirement'),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          children: [
            Tag(DutyType.displayNames[job.dutyType] ?? job.dutyType),
            Tag(FrequencyOfCare.displayNames[job.frequencyOfCare] ?? job.frequencyOfCare),
            if (job.area != null && job.area!.isNotEmpty) Tag(job.area!),
            for (final lang in job.languages) Tag(Language.displayNames[lang] ?? lang),
            if (job.preferredGender != null) Tag(capitalize(job.preferredGender!)),
            if (job.preferredReligion != null)
              Tag(Religion.displayNames[job.preferredReligion] ?? job.preferredReligion!),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(job.description),
      ],
    );
  }
}
