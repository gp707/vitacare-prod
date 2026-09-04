import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/messages_bell.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../widgets/job_detail_card.dart';
import '../widgets/job_poster_contact_card.dart';

/// Every job AND organisation requirement the caregiver is currently
/// accepted onto or has completed, merged into one list — the same "one
/// section covers both" merge as JobsScreen (see "NurseNow" in CLAUDE.md
/// for why the underlying data still lives in two separate backend
/// tables). A caregiver can hold more than one accepted job/requirement at
/// once, so this is a list, not a single item — the browse endpoints only
/// list active postings, and an accepted one closes immediately, so
/// without this screen an assigned caregiver would have no way to see its
/// details again or mark it complete. The "MyJobs" bottom-nav tab,
/// reachable regardless of current verification status, so it still shows
/// past assignments even after the caregiver has completed everything
/// (durable history — completed items stay listed).
class MyAssignmentScreen extends ConsumerStatefulWidget {
  const MyAssignmentScreen({super.key});

  @override
  ConsumerState<MyAssignmentScreen> createState() => _MyAssignmentScreenState();
}

class _MyAssignmentScreenState extends ConsumerState<MyAssignmentScreen> {
  List<JobModel> _jobs = [];
  List<OrganisationRequirementModel> _requirements = [];
  bool _loading = true;
  String? _errorMessage;
  String? _completingId;
  // Defaults on — a caregiver's list is dominated by active engagements
  // day to day; completed ones are the historical record, not what they
  // need to see first. Still one tap away to review.
  bool _hideCompleted = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final jobs = await ref.read(jobsRepositoryProvider).getAssignedJobs();
      final requirements = await ref.read(organisationOpeningsRepositoryProvider).getAssigned();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _requirements = requirements;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Closing an accepted job is the only exit from `assigned` for it — same
  /// server call as the old "Mark Complete" (job_applications.status ->
  /// completed): a caregiver-initiated close IS the completion event now,
  /// no separate "mark complete" step exists. Labeled "Close", not
  /// "Reject" — the resulting status is 'completed' (work done), and
  /// "reject" is reserved for declining/withdrawing an application before
  /// it's ever accepted (see jobs_screen.dart's _withdrawJob), a genuinely
  /// different outcome ('rejected'). The patient/family sees this as
  /// "Closed by Caregiver" on their side too (nursenow-app's
  /// _ApplicantTile), so the terminology matches on both apps.
  Future<void> _completeJob(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this job?'),
        content: Text(
          "This marks ${jobDisplayId(job)} as closed — work completed. You can apply again later if it's still "
          "open. If you don't have any other accepted jobs, you'll be shown as available for new ones again.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close Job'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _completingId = job.id);
    try {
      final stillAssigned = await ref.read(jobsRepositoryProvider).completeJob(job.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              stillAssigned
                  ? '${jobDisplayId(job)} closed.'
                  : "${jobDisplayId(job)} closed. You're now available for new jobs.",
            ),
          ),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _completingId = null);
    }
  }

  /// Same as [_completeJob], for an organisation requirement.
  Future<void> _completeRequirement(OrganisationRequirementModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this requirement?'),
        content: Text(
          "This marks ${organisationJobDisplayId(requirement)} as closed — work completed. You can apply again "
          "later if it's still open. If you don't have any other accepted jobs or requirements, you'll be shown "
          "as available for new ones again.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close Requirement'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _completingId = requirement.id);
    try {
      final verificationStatus = await ref.read(organisationOpeningsRepositoryProvider).complete(requirement.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verificationStatus == VerificationStatus.assigned
                  ? '${organisationJobDisplayId(requirement)} closed.'
                  : "${organisationJobDisplayId(requirement)} closed. You're now available for new jobs.",
            ),
          ),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _completingId = null);
    }
  }

  List<_Assignment> _mergedAssignments() {
    final assignments = <_Assignment>[
      ..._jobs.map(_JobAssignment.new),
      ..._requirements.map(_RequirementAssignment.new),
    ];
    // Newest first — the job/requirement most recently accepted is the one
    // most likely to need attention right now.
    assignments.sort((a, b) => b.decidedAt.compareTo(a.decidedAt));
    return assignments;
  }

  @override
  Widget build(BuildContext context) {
    final assignments = _mergedAssignments();
    final hasCompleted = assignments.any((a) => a.isCompleted);
    final visible = _hideCompleted ? assignments.where((a) => !a.isCompleted).toList() : assignments;
    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('MyJobs'),
        // Logout lives only on the Profile screen now (moved to the bottom
        // of the page there) — no longer duplicated in every screen's
        // AppBar.
        actions: caregiverAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 2),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_errorMessage != null)
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                    if (hasCompleted)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Hide completed jobs'),
                        value: _hideCompleted,
                        onChanged: (value) => setState(() => _hideCompleted = value),
                      ),
                    if (assignments.isEmpty && _errorMessage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          "You don't have any accepted jobs yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else if (visible.isEmpty && _errorMessage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          'All your accepted jobs are completed and hidden. Turn off "Hide completed jobs" to see them.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final assignment in visible) ...[
                      if (assignment is _JobAssignment)
                        _AssignedJobCard(
                          job: assignment.job,
                          completing: _completingId == assignment.job.id,
                          onMarkComplete: () => _completeJob(assignment.job),
                        )
                      else if (assignment is _RequirementAssignment)
                        _AssignedRequirementCard(
                          requirement: assignment.requirement,
                          completing: _completingId == assignment.requirement.id,
                          onMarkComplete: () => _completeRequirement(assignment.requirement),
                        ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Common shape the merged list sorts/filters by.
abstract class _Assignment {
  DateTime get decidedAt;
  bool get isCompleted;
}

class _JobAssignment extends _Assignment {
  final JobModel job;
  _JobAssignment(this.job);
  @override
  DateTime get decidedAt =>
      DateTime.parse(job.myApplication?.acceptedAt ?? job.myApplication?.appliedAt ?? job.postedAt);
  @override
  bool get isCompleted => job.myApplication?.status == JobApplicationStatus.completed;
}

class _RequirementAssignment extends _Assignment {
  final OrganisationRequirementModel requirement;
  _RequirementAssignment(this.requirement);
  @override
  DateTime get decidedAt => DateTime.parse(
        requirement.myApplication?.acceptedAt ?? requirement.myApplication?.appliedAt ?? requirement.postedAt,
      );
  @override
  bool get isCompleted => requirement.myApplication?.status == JobApplicationStatus.completed;
}

class _AssignedJobCard extends StatelessWidget {
  final JobModel job;
  final bool completing;
  final VoidCallback onMarkComplete;

  const _AssignedJobCard({required this.job, required this.completing, required this.onMarkComplete});

  @override
  Widget build(BuildContext context) {
    final isCompleted = job.myApplication?.status == JobApplicationStatus.completed;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // A bold border on a light green shade clearly separates each
        // job/requirement card from the next — matches the browse-list
        // cards in jobs_screen.dart. Red while still active/assigned, grey
        // once the caregiver has closed it (no longer "live" work).
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: isCompleted ? AppColors.textSecondary : AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobDetailCard(job: job),
          const SizedBox(height: AppSpacing.md),
          if (isCompleted)
            // Completion is always caregiver-initiated (there's no
            // admin/patient path to it) — say so explicitly, and "closed"
            // (work done), never "rejected" (which would misread as the
            // patient/employer having ended it).
            const Text(
              'You closed this job — work completed',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
            )
          else ...[
            const Text(
              'You were accepted for this job',
              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: _CloseButton(completing: completing, onPressed: onMarkComplete, label: 'Close Job'),
            ),
          ],
          if (job.myApplication != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ApplicationTimeline(job.myApplication!),
          ],
          if (job.jobPoster != null) ...[
            const SizedBox(height: AppSpacing.md),
            JobPosterContactCard(poster: job.jobPoster!, showPhone: !isCompleted),
          ],
        ],
      ),
    );
  }
}

class _AssignedRequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final bool completing;
  final VoidCallback onMarkComplete;

  const _AssignedRequirementCard({required this.requirement, required this.completing, required this.onMarkComplete});

  @override
  Widget build(BuildContext context) {
    final isCompleted = requirement.myApplication?.status == JobApplicationStatus.completed;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // A bold border on a light green shade clearly separates each
        // job/requirement card from the next — matches the browse-list
        // cards in jobs_screen.dart. Red while still active/assigned, grey
        // once the caregiver has closed it (no longer "live" work).
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: isCompleted ? AppColors.textSecondary : AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Job in Posted by Organisation '
            '${requirement.city != null ? (City.displayNames[requirement.city] ?? requirement.city!) : ''}',
            style: const TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.bold, color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(organisationJobDisplayId(requirement),
              style: const TextStyle(fontSize: AppTypography.small, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
          const SizedBox(height: AppSpacing.xs),
          Tag(
            requirement.organisationType != null
                ? OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!
                : 'Organisation',
          ),
          const SizedBox(height: 2),
          Text(
            requirement.organisationName ?? '',
            style: const TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold),
          ),
          Text(
            requirement.typeOfNurse == TypeOfNurse.others && requirement.typeOfNurseOther != null
                ? '${TypeOfNurse.displayNames[requirement.typeOfNurse]}: ${requirement.typeOfNurseOther}'
                : TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isCompleted)
            const Text(
              'You closed this requirement — work completed',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
            )
          else ...[
            const Text(
              'You were accepted for this requirement',
              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: _CloseButton(completing: completing, onPressed: onMarkComplete, label: 'Close Requirement'),
            ),
          ],
          if (requirement.myApplication != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ApplicationTimeline(requirement.myApplication!),
          ],
        ],
      ),
    );
  }
}

/// The caregiver-facing "done" action on an accepted job/requirement — an
/// outlined green button with a check-circle icon, distinct from
/// jobs_screen.dart's filled-green Apply and red-outline Reject (this isn't
/// either of those: it's a positive but confirm-first action, so it keeps
/// the outline treatment rather than a solid fill). Shared by
/// _AssignedJobCard and _AssignedRequirementCard.
class _CloseButton extends StatelessWidget {
  final bool completing;
  final VoidCallback onPressed;
  final String label;

  const _CloseButton({required this.completing, required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: completing ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.success,
        side: const BorderSide(color: AppColors.success),
      ),
      icon: completing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success),
            )
          : const Icon(Icons.task_alt, size: 18),
      label: Text(label),
    );
  }
}
