import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/scope_of_work_button.dart';
import '../../../app/duty_requirements_button.dart';
import '../../../core/providers.dart';

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
      style: const TextStyle(fontSize: AppTypography.small, fontWeight: FontWeight.bold, color: AppColors.success),
    );
  }
}

class Tag extends StatelessWidget {
  final String label;
  // Marks a tag as highlighter-pen yellow instead of the default neutral
  // pill — used to call out the gender fields specifically (patient's own
  // gender, and the caregiver-preferred gender) so they stand out at a
  // glance among the rest of the About Patient/Requirement tags.
  final bool highlighted;

  const Tag(this.label, {super.key, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: highlighted ? Colors.yellow : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
        child: Text(label, style: const TextStyle(fontSize: AppTypography.small)),
      ),
    );
  }
}

/// The salary figure — always the most important number on a card, so it
/// gets its own green banner rather than reading as just another field.
/// Shared by JobDetailCard (jobs) and _RequirementCard in jobs_screen.dart
/// (organisation requirements), which carry the same amount/frequency shape.
class SalaryBadge extends StatelessWidget {
  final String amount;
  final String? frequencyOfCare;

  const SalaryBadge({super.key, required this.amount, required this.frequencyOfCare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.success),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
              '$amount/${salaryUnit(frequencyOfCare)}',
              textAlign: TextAlign.center,
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
/// icon rather than relying on a caregiver reading the English label — the
/// icon marks the category (a clock always means timing, a pin always means
/// place), the text still carries the actual value. Used on the collapsed
/// job card header only, where a caregiver decides whether to even open a
/// listing; the expanded detail section below still uses plain [Tag] chips.
class IconField extends StatelessWidget {
  final IconData icon;
  final String text;

  const IconField({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: AppColors.primaryDark),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.bold, color: AppColors.success),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// The label portion (before the colon) of every field line below — "Job
// Id", "Type Of Care", "Scope Of Work", "Patient Provides" — is bold black,
// distinct from the dark green value that follows it. Matches nursenow-app's
// own job card field lines.
const _fieldLabelStyle = TextStyle(
    fontSize: AppTypography.body, color: AppColors.textPrimary, fontWeight: FontWeight.bold);
const _fieldValueStyle = TextStyle(
    fontSize: AppTypography.body, color: AppColors.success, fontWeight: FontWeight.bold);
const _fieldLinkStyle = TextStyle(
    fontSize: AppTypography.body,
    color: AppColors.success,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline);

/// The job's real display id, set apart from the "Job Id" label (bold
/// black, like every other field label) in its own larger bold green, same
/// visual weight a hospital chart gives a record/MRN number.
class _JobIdLine extends StatelessWidget {
  final JobModel job;

  const _JobIdLine({required this.job});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Job Id: ', style: _fieldLabelStyle),
          TextSpan(
            text: jobDisplayId(job),
            style: const TextStyle(
                fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

/// A single, uniformly-styled "Label: Value" record line — the value is
/// either plain text or, when [isLink] is set, a tappable "Click Here"
/// styled like a link, opening whatever [onTap] shows (the derived Scope
/// of Work or duty-requirements popup).
class _FieldLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isLink;
  final VoidCallback? onTap;

  const _FieldLine({required this.label, required this.value, this.isLink = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: _fieldLabelStyle),
          TextSpan(text: value, style: isLink ? _fieldLinkStyle : _fieldValueStyle),
        ],
      ),
    );
    if (onTap == null) return text;
    return InkWell(onTap: onTap, child: text);
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
class JobDetailCard extends ConsumerWidget {
  final JobModel job;

  const JobDetailCard({super.key, required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _JobHeaderContent(job: job),
        const SizedBox(height: AppSpacing.xs),
        // Pushes a dedicated full-screen page rather than expanding inline —
        // on a small phone the About Patient/Requirement tags and free-text
        // description used to wrap into a cramped card-width column; a full
        // screen gives them room to breathe. Getting back out is just the
        // standard AppBar back button there (see JobFullDetailScreen).
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => JobFullDetailScreen(job: job)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'View Full Details about Patient Requirements',
                  style: TextStyle(
                    fontSize: AppTypography.small,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Icon(Icons.open_in_full, size: 15, color: AppColors.primary),
            ],
          ),
        ),
      ],
    );
  }
}

/// The header content every job listing shows up front — display id,
/// urgency, salary, start date, duty type + city, posted date — shared
/// between the collapsed [JobDetailCard] (a preview, so a caregiver can
/// decide whether to open the full page) and [JobFullDetailScreen] (a
/// self-contained full page, so it doesn't read as missing the basics
/// once you're actually on it).
class _JobHeaderContent extends ConsumerWidget {
  final JobModel job;

  const _JobHeaderContent({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applyByWindowDays = ref.watch(applyByWindowDaysProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.yellow,
                child: Text(
                  'Job in ${jobPostedByLabel(job)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                urgencyLabel(job.daysLeftToApply(applyByWindowDays)),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: AppTypography.small,
                  fontWeight: FontWeight.bold,
                  color: urgencyColor(job.daysLeftToApply(applyByWindowDays)),
                ),
              ),
            ),
          ],
        ),
        if (job.salaryAmount != null || job.startDate != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (job.salaryAmount != null)
                Expanded(child: SalaryBadge(amount: job.salaryAmount!, frequencyOfCare: job.frequencyOfCare)),
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
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconField(icon: Icons.access_time, text: DutyType.displayNames[job.dutyType] ?? job.dutyType),
            // Only ever set on a NurseNow individual's own posting — null
            // for an admin-posted job, so this tag doesn't show there.
            if (job.careDuration != null)
              IconField(
                icon: Icons.date_range,
                text: CareDuration.displayNames[job.careDuration!] ?? job.careDuration!,
              ),
            IconField(
              icon: Icons.location_on,
              text: [
                City.displayNames[job.city] ?? job.city,
                if (job.area != null && job.area!.isNotEmpty) job.area!,
              ].join(' · '),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _JobIdLine(job: job)),
            if (job.careReceiver != null) ...[
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _FieldLine(
                  label: 'Type Of Care',
                  value: CareTier.displayNames[deriveCareTier(job.careReceiver!)] ??
                      deriveCareTier(job.careReceiver!),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (job.careReceiver != null) ...[
              Expanded(
                child: _FieldLine(
                  label: 'Scope Of Work',
                  value: 'Click Here',
                  isLink: true,
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => ScopeOfWorkDialog(
                      tier: deriveCareTier(job.careReceiver!),
                      repository: ref.read(scopeOfWorkRepositoryProvider),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: _FieldLine(
                label: 'Patient Provides',
                value: 'Click Here',
                isLink: true,
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => DutyRequirementsDialog(
                    dutyType: job.dutyType,
                    repository: ref.read(dutyRequirementsRepositoryProvider),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Posted: ${formatDate(DateTime.parse(job.postedAt))}',
          style: const TextStyle(fontSize: AppTypography.small, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// The full-screen "everything about this job" page — reached by tapping
/// "View Full Details" on the (deliberately compact) [JobDetailCard]. Full
/// width and free to scroll as long as it needs, so the About Patient /
/// About Nurse-Caregiver Requirement tag sections and the free-text
/// description — the parts most likely to wrap awkwardly in a card on a
/// small phone — have room to read clearly. Getting back out is just the
/// AppBar's own standard back button, same as leaving any other screen in
/// this app.
class JobFullDetailScreen extends StatelessWidget {
  final JobModel job;

  const JobFullDetailScreen({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(jobDisplayId(job))),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _JobHeaderContent(job: job),
              if (job.careReceiver != null) ...[
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                const SectionLabel('About Patient'),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  children: [
                    Tag('${job.careReceiver!.age} yrs'),
                    Tag(capitalize(job.careReceiver!.gender), highlighted: true),
                    Tag('${job.careReceiver!.weightKg} kg'),
                    Tag(FeedingType.displayNames[job.careReceiver!.feedingType] ?? job.careReceiver!.feedingType),
                    for (final t in job.careReceiver!.toiletAssistance)
                      Tag('Toilet: ${ToiletAssistance.displayNames[t] ?? t}'),
                    if (job.careReceiver!.hasMedicalCondition)
                      for (final c in job.careReceiver!.medicalConditions)
                        Tag('Medical Condition: ${MedicalCondition.displayNames[c] ?? c}')
                    else
                      const Tag('Medical Condition: None'),
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
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: AppTypography.small, fontStyle: FontStyle.italic),
                  ),
                ],
                if (job.careReceiver!.toiletAssistanceOther != null &&
                    job.careReceiver!.toiletAssistanceOther!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Other toilet assistance: ${job.careReceiver!.toiletAssistanceOther!}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: AppTypography.small, fontStyle: FontStyle.italic),
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
                  // Only ever set on a NurseNow individual's own posting —
                  // null for an admin-posted job.
                  if (job.careDuration != null)
                    Tag(CareDuration.displayNames[job.careDuration!] ?? job.careDuration!),
                  for (final lang in job.languages) Tag(Language.displayNames[lang] ?? lang),
                  if (job.preferredGender != null)
                    Tag('Preferred Gender: ${capitalize(job.preferredGender!)}', highlighted: true),
                  if (job.preferredReligion != null)
                    Tag('Preferred Religion: ${Religion.displayNames[job.preferredReligion] ?? job.preferredReligion!}'),
                ],
              ),
              if (job.description != null && job.description!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const SectionLabel('More Details'),
                const SizedBox(height: AppSpacing.xs),
                Text(job.description!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The caregiver's own full action history on a job/requirement — every
/// transition with who did it and exactly when, newest first: applied,
/// re-applied, accepted, and now closed (a caregiver-initiated completion
/// of an accepted engagement) or declined. Shared between the Jobs list
/// (still-undecided/declined applications) and MyJobs (accepted/closed
/// ones) so the same timeline renders identically wherever a caregiver's
/// own application shows up — "you" always means an action taken here in
/// NurseJobs; "employer" covers whoever posted the job/requirement
/// deciding on it (admin, or the NurseNow patient/organisation themselves
/// — decidedByAdmin, despite the name, covers both, since there's no way
/// to tell those two apart from this flag alone).
class ApplicationTimeline extends StatefulWidget {
  final MyApplicationModel application;

  const ApplicationTimeline(this.application, {super.key});

  @override
  State<ApplicationTimeline> createState() => _ApplicationTimelineState();
}

class _ApplicationTimelineState extends State<ApplicationTimeline> {
  // Fixed per-row heights, rather than relying on inherited text-theme
  // metrics — the ambient DefaultTextStyle isn't stable enough to guess at
  // "roughly 3 lines" of pixels; picking a known font size and row height
  // instead makes the maxHeight below (and whether rows actually overflow
  // it) exact instead of a fragile trial-and-error guess.
  static const _fontSize = 13.0;
  static const _rowHeight = 20.0;
  static const _reasonRowHeight = 36.0; // a "Declined + Reason" row wraps to two lines
  // Strictly less than 4 plain rows (80) and strictly more than 3 (60), so
  // a 4th entry always genuinely overflows and the scrollbar is never shown
  // without something real to scroll to.
  static const _maxHeight = 66.0;

  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final entries = <MapEntry<DateTime, String>>[];
    if (application.appliedAt != null) {
      final at = DateTime.parse(application.appliedAt!).toLocal();
      entries.add(MapEntry(at, 'Applied by you: ${formatDateTime(at)}'));
    }
    // Full detail on a re-apply — reappliedAt survives even after this same
    // apply clears rejectedAt/completedAt, so it's the only place left that
    // shows a prior rejection/close ever happened at all (see
    // JobApplicationsRepository.upsert).
    if (application.reappliedAt != null) {
      final at = DateTime.parse(application.reappliedAt!).toLocal();
      entries.add(MapEntry(at, 'Re-applied by you: ${formatDateTime(at)}'));
    }
    if (application.acceptedAt != null) {
      final at = DateTime.parse(application.acceptedAt!).toLocal();
      entries.add(MapEntry(at, 'Accepted by employer: ${formatDateTime(at)}'));
    }
    // A caregiver-initiated close of an accepted job — the only path to
    // 'completed', so this is always "by you", never the employer's doing.
    if (application.status == JobApplicationStatus.completed && application.completedAt != null) {
      final at = DateTime.parse(application.completedAt!).toLocal();
      var text = 'Closed by you: ${formatDateTime(at)}';
      if (application.closeReason != null) {
        text = '$text\nReason: ${CaregiverCloseReason.displayNames[application.closeReason] ?? application.closeReason}';
      }
      entries.add(MapEntry(at, text));
    }
    if (application.status == JobApplicationStatus.rejected && application.rejectedAt != null) {
      final at = DateTime.parse(application.rejectedAt!).toLocal();
      final label = application.decidedByAdmin ? 'Declined by employer' : 'Declined by you';
      var text = '$label: ${formatDateTime(at)}';
      if (application.declineReason != null && application.declineReason!.isNotEmpty) {
        text = '$text\nReason: ${application.declineReason!}';
      }
      entries.add(MapEntry(at, text));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    // Newest first — the current status is the one worth seeing without
    // having to scroll for it.
    entries.sort((a, b) => b.key.compareTo(a.key));

    final totalHeight = entries.fold<double>(
      0,
      (sum, entry) => sum + (entry.value.contains('\n') ? _reasonRowHeight : _rowHeight),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: Scrollbar(
        controller: _controller,
        // Only forced visible when there's genuinely something to scroll to
        // — otherwise a full-track, undraggable thumb looks broken.
        thumbVisibility: totalHeight > _maxHeight,
        child: ListView(
          controller: _controller,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final entry in entries)
              SizedBox(
                height: entry.value.contains('\n') ? _reasonRowHeight : _rowHeight,
                child: Text(
                  entry.value,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                    fontSize: _fontSize,
                  ),
                ),
              ),
          ],
        ),
      ),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today, size: 14, color: AppColors.error),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.title,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
