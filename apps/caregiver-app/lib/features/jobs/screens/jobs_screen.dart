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

/// Unified list of active postings — admin/individual jobs AND organisation
/// (hospital/rehab/clinic) requirements shown together, sorted by post
/// date. Organisation requirements previously lived on their own separate
/// "Openings" tab; merged into one Jobs section on explicit request so a
/// caregiver only has to check one place. Applying is gated server-side
/// (JOB_001 for jobs, the same eligibility rule for requirements) to
/// available/assigned caregivers only; a caregiver in any other status sees
/// the server's rejection message when they try, rather than the buttons
/// being hidden entirely.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  List<JobModel> _jobs = [];
  List<OrganisationRequirementModel> _requirements = [];
  bool _loading = true;
  String? _errorMessage;
  final Set<String> _applyingId = {};
  // Defaults off — an organisation requirement the caregiver is done with
  // (rejected by either side, or closed themselves after being accepted —
  // see _Listing.isHiddenByDefault) is hidden by default to keep the list
  // focused on what's still open to them. One tap away to see everything.
  // Jobs are never hidden this way — a rejected/completed job can always be
  // re-applied to, so it stays visible with its own "Apply Again" action.
  bool _showAllJobs = false;

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
      final jobs = await ref.read(jobsRepositoryProvider).listActiveJobs();
      final requirements = await ref.read(organisationOpeningsRepositoryProvider).listActive();
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

  Future<void> _applyToJob(JobModel job, String status) async {
    setState(() => _applyingId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).applyToJob(job.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _applyingId.remove(job.id));
    }
  }

  Future<void> _applyToRequirement(OrganisationRequirementModel requirement, String status) async {
    setState(() => _applyingId.add(requirement.id));
    try {
      await ref.read(organisationOpeningsRepositoryProvider).apply(requirement.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _applyingId.remove(requirement.id));
    }
  }

  /// A plain, pre-apply decline — the caregiver has never applied to this
  /// job at all, they're just saying no from the browse list. Every reject
  /// action needs a confirmation first (see [_withdrawJob], the other path
  /// that lands on the same 'rejected' status), so this always shows the
  /// dialog before calling through to [_applyToJob].
  Future<void> _rejectJob(JobModel job) async {
    if (!await _confirmReject(jobDisplayId(job))) return;
    await _applyToJob(job, JobApplicationStatus.rejected);
  }

  /// Same as [_rejectJob], for an organisation requirement.
  Future<void> _rejectRequirement(OrganisationRequirementModel requirement) async {
    if (!await _confirmReject(organisationJobDisplayId(requirement))) return;
    await _applyToRequirement(requirement, JobApplicationStatus.rejected);
  }

  Future<bool> _confirmReject(String displayId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this job?'),
        content: const Text('Are you sure you want to reject the job?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Withdraws a still-`applied` (not yet accepted) application — reuses
  /// the exact same apply endpoint with status 'rejected' that the
  /// pre-apply "Reject" button already calls (a caregiver-initiated
  /// withdrawal and a caregiver declining outright are the same server
  /// action: `decided_by` stays null either way, which is what tells the
  /// patient/family's own view "the caregiver did this", not them). Once
  /// this lands, the patient can no longer accept this caregiver for the
  /// job (JOB_007 backstops it server-side even if the UI somehow let
  /// them try), and the caregiver's phone number drops out of the
  /// patient's view of this application.
  Future<void> _withdrawJob(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this job?'),
        content: const Text(
          "Are you sure you want to reject the job? This withdraws your application — the patient/employer "
          "won't be able to accept you for it anymore, and your contact details will no longer be shown to them.",
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
    if (confirmed != true) return;
    await _applyToJob(job, JobApplicationStatus.rejected);
  }

  /// Same as [_withdrawJob], for an organisation requirement.
  Future<void> _withdrawRequirement(OrganisationRequirementModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject this requirement?'),
        content: const Text(
          "Are you sure you want to reject the job? This withdraws your application — the organisation "
          "won't be able to accept you for it anymore, and your contact details will no longer be shown to them.",
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
    if (confirmed != true) return;
    await _applyToRequirement(requirement, JobApplicationStatus.rejected);
  }

  List<_Listing> _mergedListings() {
    final listings = <_Listing>[
      ..._jobs.map(_JobListing.new),
      ..._requirements.map(_RequirementListing.new),
    ];
    listings.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return listings;
  }

  @override
  Widget build(BuildContext context) {
    final listings = _mergedListings();
    final hasHiddenJobs = listings.any((l) => l.isHiddenByDefault);
    final visible = _showAllJobs ? listings : listings.where((l) => !l.isHiddenByDefault).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
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
            child: const Text('Logout', style: TextStyle(color: Colors.white, fontSize: AppTypography.small)),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 1),
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
                    if (hasHiddenJobs)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show All Jobs'),
                        subtitle: const Text(
                          'Includes organisation requirements you were rejected from, or closed yourself',
                        ),
                        value: _showAllJobs,
                        onChanged: (value) => setState(() => _showAllJobs = value),
                      ),
                    if (listings.isEmpty && _errorMessage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          'No jobs posted right now. Pull down to refresh.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else if (visible.isEmpty && _errorMessage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          'No jobs you can currently apply to. Turn on "Show All Jobs" to see organisation '
                          'requirements you were rejected from or closed yourself.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final listing in visible) ...[
                      if (listing is _JobListing)
                        _JobCard(
                          job: listing.job,
                          isApplying: _applyingId.contains(listing.job.id),
                          onApply: () => _applyToJob(listing.job, JobApplicationStatus.applied),
                          onReject: () => _rejectJob(listing.job),
                          onWithdraw: () => _withdrawJob(listing.job),
                        )
                      else if (listing is _RequirementListing)
                        _RequirementCard(
                          requirement: listing.requirement,
                          isApplying: _applyingId.contains(listing.requirement.id),
                          onApply: () => _applyToRequirement(listing.requirement, JobApplicationStatus.applied),
                          onReject: () => _rejectRequirement(listing.requirement),
                          onWithdraw: () => _withdrawRequirement(listing.requirement),
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

/// Common shape the merged list sorts by — a job and an organisation
/// requirement have nothing else in common worth abstracting over (see
/// _JobCard/_RequirementCard below, which stay entirely separate widgets).
abstract class _Listing {
  DateTime get postedAt;

  /// True once this listing is done from the caregiver's own point of
  /// view and there's nothing further they can do about it. Requirements
  /// hide once rejected (by the org, or by closing/withdrawing themselves
  /// before being accepted) or closed themselves after being accepted
  /// (`completed`) — the requirement reopens to active for everyone else,
  /// but this caregiver's own engagement with it is over.
  bool get isHiddenByDefault;
}

class _JobListing extends _Listing {
  final JobModel job;
  _JobListing(this.job);
  @override
  DateTime get postedAt => DateTime.parse(job.postedAt);
  // Jobs are never hidden by default, even once rejected/completed — this
  // list only ever contains active jobs, and a rejected/completed
  // application on an active job can always be re-applied to (see
  // _JobCard's "Apply Again" button), so it stays actionable and visible.
  @override
  bool get isHiddenByDefault => false;
}

class _RequirementListing extends _Listing {
  final OrganisationRequirementModel requirement;
  _RequirementListing(this.requirement);
  @override
  DateTime get postedAt => DateTime.parse(requirement.postedAt);
  @override
  bool get isHiddenByDefault =>
      requirement.myApplication?.status == JobApplicationStatus.rejected ||
      requirement.myApplication?.status == JobApplicationStatus.completed;
}

class _JobCard extends StatelessWidget {
  final JobModel job;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onReject;
  final VoidCallback onWithdraw;

  const _JobCard({
    required this.job,
    required this.isApplying,
    required this.onApply,
    required this.onReject,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // A bold red border on a light green shade clearly separates each
        // job/requirement card from the next — this browse list only ever
        // shows active/live postings, so the border is always red (the
        // "genuinely live" color, matching nursenow's own job cards).
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobDetailCard(job: job),
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (job.myApplication != null) ...[
            ApplicationTimeline(job.myApplication!),
            // A caregiver can withdraw anytime while the patient/employer
            // still hasn't decided — once accepted, closing happens from
            // MyJobs instead (see my_assignment_screen.dart). A rejected or
            // completed application can be re-applied to instead, as long
            // as the job is still live — this list only ever shows active
            // jobs, so that's always true here.
            if (job.myApplication!.status == JobApplicationStatus.applied) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(width: double.infinity, child: _RejectButton(onPressed: onWithdraw, label: 'Reject Job')),
            ] else if (job.myApplication!.status == JobApplicationStatus.rejected ||
                job.myApplication!.status == JobApplicationStatus.completed) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: _ApplyButton(onPressed: onApply, label: 'Apply Again', icon: Icons.refresh),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(child: _ApplyButton(onPressed: onApply, label: 'Apply')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _RejectButton(onPressed: onReject, label: 'Reject')),
              ],
            ),
        ],
      ),
    );
  }
}

/// The caregiver-facing "yes" action — filled solid green with a check, so
/// it reads as affirmative by shape and color alone, not just the word.
/// Shared by _JobCard and _RequirementCard; [icon] defaults to a plain
/// check but "Apply Again" (after a rejected/completed application) uses a
/// refresh icon instead, since that action isn't a first-time apply.
class _ApplyButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const _ApplyButton({required this.onPressed, required this.label, this.icon = Icons.check});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// The caregiver-facing "no" action — a red outline with a cross, distinct
/// from [_ApplyButton] in both shape and color, not just the word. Shared by
/// every reject/withdraw path across _JobCard and _RequirementCard.
class _RejectButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const _RejectButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
      ),
      icon: const Icon(Icons.close, size: 18),
      label: Text(label),
    );
  }
}

class _RequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onReject;
  final VoidCallback onWithdraw;

  const _RequirementCard({
    required this.requirement,
    required this.isApplying,
    required this.onApply,
    required this.onReject,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // A bold red border on a light green shade clearly separates each
        // job/requirement card from the next — this browse list only ever
        // shows active/live postings, so the border is always red (the
        // "genuinely live" color, matching nursenow's own job cards).
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.error, width: 2.5),
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
          _Tag(
            requirement.organisationType != null
                ? OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!
                : 'Organisation',
          ),
          const SizedBox(height: 2),
          Text(
            requirement.organisationName ?? '',
            style: const TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold),
          ),
          if (requirement.organisationType != null || requirement.city != null)
            Text(
              [
                if (requirement.organisationType != null)
                  OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!,
                if (requirement.city != null) City.displayNames[requirement.city] ?? requirement.city!,
                if (requirement.area != null && requirement.area!.isNotEmpty) requirement.area!,
              ].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          if (requirement.salaryAmount != null || organisationScheduleLabel(requirement) != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (requirement.salaryAmount != null)
                  Expanded(
                    child: SalaryBadge(
                      amount: requirement.salaryAmount!.toString(),
                      frequencyOfCare: requirement.frequencyOfCare,
                    ),
                  ),
                if (requirement.salaryAmount != null && organisationScheduleLabel(requirement) != null)
                  const SizedBox(width: AppSpacing.xs),
                if (organisationScheduleLabel(requirement) != null)
                  Expanded(child: BlinkingStartDateBadge(label: organisationScheduleLabel(requirement)!)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _Tag(TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse),
              _Tag(requirement.accommodationProvided ? 'Accommodation provided' : 'No accommodation'),
              _Tag(requirement.foodProvided ? 'Food provided' : 'No food'),
            ],
          ),
          if (requirement.specialSkills != null && requirement.specialSkills!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(requirement.specialSkills!),
          ],
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (requirement.myApplication != null) ...[
            ApplicationTimeline(requirement.myApplication!),
            if (requirement.myApplication!.status == JobApplicationStatus.applied) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: _RejectButton(onPressed: onWithdraw, label: 'Reject Requirement'),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(child: _ApplyButton(onPressed: onApply, label: 'Apply')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _RejectButton(onPressed: onReject, label: 'Reject')),
              ],
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Text(label, style: const TextStyle(fontSize: AppTypography.small)),
    );
  }
}

/// Shows what actually happened to this application and when, instead of a
/// single bare status word — in particular this is what tells "you
/// declined it" (self) apart from "the employer declined you" (admin
/// rejected a still-applied application, or undid a prior acceptance —
/// both read the same to the caregiver: the employer said no). Shared by
/// both _JobCard and _RequirementCard — MyApplicationModel is the same
/// shape either way.
// ApplicationTimeline moved to job_detail_card.dart — shared with MyJobs.
