import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/scope_of_work_button.dart';

String formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// Seconds are included (not just hours:minutes) so two actions taken within
// the same minute — e.g. one caregiver applying right after another — still
// display in a visibly distinguishable, correctly ordered sequence. The
// underlying DateTime already carries full precision from the backend
// (Postgres timestamptz); this only affects what's shown, not how anything
// is sorted (sorting already compares full DateTime/ISO values).
String formatDateTime(DateTime date) =>
    '${formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:'
    '${date.second.toString().padLeft(2, '0')}';

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

/// Salary's unit follows Frequency of Care — a 'daily' job's figure is a
/// per-day rate, everything else reads as monthly.
String salaryUnit(String? frequencyOfCare) => frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month';

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

/// Job header (display id, urgency, salary), the About Patient / About
/// Nurse-Caregiver Requirement sections, and the free-text description —
/// everything about a job except caregiver-action
/// controls. Shared between the Jobs list card (which appends Apply/Reject)
/// and the MyJobs tab (which appends an "Accepted" status
/// instead), so the same care-needs picture renders identically wherever a
/// caregiver sees a job.
///
/// Collapsed by default: with many jobs in the list, cards full of identical
/// tag sections were hard to tell apart at a glance. Only the header (job
/// number, urgency, salary, start date, duty type + city, posted date) shows
/// up front; the patient/requirement detail is a tap away, one card at a
/// time, so scanning the list stays fast.
class JobDetailCard extends StatefulWidget {
  final JobModel job;

  const JobDetailCard({super.key, required this.job});

  @override
  State<JobDetailCard> createState() => _JobDetailCardState();
}

class _JobDetailCardState extends State<JobDetailCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                jobDisplayId(job),
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
        const SizedBox(height: AppSpacing.xs),
        Tag(jobPostedByLabel(job)),
        if (job.salaryAmount != null || job.startDate != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (job.salaryAmount != null)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Text(
                      '₹${job.salaryAmount}/${salaryUnit(job.frequencyOfCare)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ),
              if (job.salaryAmount != null && job.startDate != null) const SizedBox(width: AppSpacing.xs),
              if (job.startDate != null)
                Expanded(
                  child: BlinkingStartDateBadge(
                    label: 'Start: ${formatDate(DateTime.parse(job.startDate!))}',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${DutyType.displayNames[job.dutyType] ?? job.dutyType} in '
          '${City.displayNames[job.city] ?? job.city}'
          '${job.careReceiver != null ? ' · ${capitalize(job.careReceiver!.gender)} Patient' : ''}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'Posted: ${formatDate(DateTime.parse(job.postedAt))}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _expanded ? 'Hide details' : 'Show details',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
        if (job.careReceiver != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: ScopeOfWorkButton(careReceiver: job.careReceiver!),
          ),
        ],
        if (_expanded) ...[
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
                Tag(Communication.displayNames[job.careReceiver!.communication] ??
                    job.careReceiver!.communication),
                Tag(FeedingType.displayNames[job.careReceiver!.feedingType] ?? job.careReceiver!.feedingType),
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
            if (job.careReceiver!.medicalConditionOther != null &&
                job.careReceiver!.medicalConditionOther!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Other condition: ${job.careReceiver!.medicalConditionOther!}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
            if (job.careReceiver!.toiletAssistanceOther != null &&
                job.careReceiver!.toiletAssistanceOther!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Other toilet assistance: ${job.careReceiver!.toiletAssistanceOther!}',
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
              // Always set on an active job (only ever null for a NurseNow
              // individual's still-pending_review posting, which caregivers
              // never see — GET /caregiver/jobs only returns active jobs).
              if (job.frequencyOfCare != null)
                Tag(FrequencyOfCare.displayNames[job.frequencyOfCare!] ?? job.frequencyOfCare!),
              if (job.area != null && job.area!.isNotEmpty) Tag(job.area!),
              for (final lang in job.languages) Tag(Language.displayNames[lang] ?? lang),
              if (job.preferredGender != null) Tag(capitalize(job.preferredGender!)),
              if (job.preferredReligion != null)
                Tag(Religion.displayNames[job.preferredReligion] ?? job.preferredReligion!),
            ],
          ),
          if (job.description != null && job.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(job.description!),
          ],
        ],
      ],
    );
  }
}

/// Pulses continuously to draw the eye to the schedule, alongside the
/// salary, at the top of every job card — same treatment on the Jobs list
/// and MyJobs (JobDetailCard is shared between both), and reused for
/// organisation-requirement cards in jobs_screen.dart/my_assignment_screen.dart.
/// Takes an already-formatted [label] (e.g. "Start: 2026-09-01" for a job,
/// or the date-range/specific-days text from `organisationScheduleLabel`
/// for an org requirement) rather than a raw date, since the two callers'
/// text isn't the same shape.
class BlinkingStartDateBadge extends StatefulWidget {
  final String label;

  const BlinkingStartDateBadge({super.key, required this.label});

  @override
  State<BlinkingStartDateBadge> createState() => _BlinkingStartDateBadgeState();
}

class _BlinkingStartDateBadgeState extends State<BlinkingStartDateBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          border: Border.all(color: AppColors.error, width: 1.5),
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.error,
          ),
        ),
      ),
    );
  }
}
