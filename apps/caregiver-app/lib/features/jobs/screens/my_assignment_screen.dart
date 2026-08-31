import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../app/rate_card_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
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

  /// Rejecting an accepted job is the only exit from `assigned` for it —
  /// same server call as the old "Mark Complete" (job_applications.status
  /// -> completed), relabeled since a caregiver-initiated reject IS the
  /// completion event now; no separate "mark complete" step exists. The
  /// patient/family sees this as "closed by the caregiver" on their side
  /// (see nursenow-app's _DecidedApplicantTile — kept as "closed" there,
  /// distinct from a pre-acceptance decline which reads as "rejected", so
  /// the patient can always tell the two outcomes apart).
  Future<void> _completeJob(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this job?'),
        content: Text(
          "This marks ${jobDisplayId(job)} as rejected. If you don't have any other accepted jobs, "
          "you'll be shown as available for new ones again.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject Job'),
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
                  ? '${jobDisplayId(job)} rejected.'
                  : "${jobDisplayId(job)} rejected. You're now available for new jobs.",
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

  Future<void> _completeRequirement(OrganisationRequirementModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this requirement?'),
        content: Text(
          "This marks ${organisationJobDisplayId(requirement)} as rejected. If you don't have any other "
          "accepted jobs or requirements, you'll be shown as available for new ones again.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject Requirement'),
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
                  ? '${organisationJobDisplayId(requirement)} rejected.'
                  : "${organisationJobDisplayId(requirement)} rejected. You're now available for new jobs.",
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
        title: const Text('MyJobs'),
        actions: [
          const RateCardButton(),
          const WhatsAppHelpButton(),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              final navigator = Navigator.of(context);
              ref.read(sessionProvider.notifier).logout().then((_) {
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              });
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
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
        // A bold, dark border clearly separates each job/requirement card
        // from the next — matches the browse-list cards in jobs_screen.dart.
        border: Border.all(color: AppColors.textPrimary, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobDetailCard(job: job),
          const SizedBox(height: AppSpacing.md),
          if (isCompleted)
            // Completion is always caregiver-initiated (there's no
            // admin/patient path to it) — say so explicitly rather than a
            // bare "Rejected", which could read as the patient/employer
            // having ended it.
            const Text(
              'You rejected this job',
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
              child: OutlinedButton(
                onPressed: completing ? null : onMarkComplete,
                child: completing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reject Job'),
              ),
            ),
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
        // A bold, dark border clearly separates each job/requirement card
        // from the next — matches the browse-list cards in jobs_screen.dart.
        border: Border.all(color: AppColors.textPrimary, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(organisationJobDisplayId(requirement),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
          const SizedBox(height: AppSpacing.xs),
          Tag(
            requirement.organisationType != null
                ? OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!
                : 'Organisation',
          ),
          const SizedBox(height: 2),
          Text(
            requirement.organisationName ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (requirement.salaryAmount != null || organisationScheduleLabel(requirement) != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (requirement.salaryAmount != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Text(
                        '₹${requirement.salaryAmount}/${salaryUnit(requirement.frequencyOfCare)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.success),
                      ),
                    ),
                  ),
                if (requirement.salaryAmount != null && organisationScheduleLabel(requirement) != null)
                  const SizedBox(width: AppSpacing.xs),
                if (organisationScheduleLabel(requirement) != null)
                  Expanded(child: BlinkingStartDateBadge(label: organisationScheduleLabel(requirement)!)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (isCompleted)
            const Text(
              'You rejected this requirement',
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
              child: OutlinedButton(
                onPressed: completing ? null : onMarkComplete,
                child: completing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reject Requirement'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
