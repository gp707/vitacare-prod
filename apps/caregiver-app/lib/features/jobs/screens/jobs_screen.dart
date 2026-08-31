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
            child: const Text('Logout', style: TextStyle(color: Colors.white, fontSize: 13)),
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
        // A bold, dark border clearly separates each job/requirement card
        // from the next — easier to tell listings apart at a glance than
        // the thin default outline used elsewhere.
        border: Border.all(color: AppColors.textPrimary, width: 2.5),
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
            _ApplicationTimeline(job.myApplication!),
            // A caregiver can withdraw anytime while the patient/employer
            // still hasn't decided — once accepted, closing happens from
            // MyJobs instead (see my_assignment_screen.dart). A rejected or
            // completed application can be re-applied to instead, as long
            // as the job is still live — this list only ever shows active
            // jobs, so that's always true here.
            if (job.myApplication!.status == JobApplicationStatus.applied) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: onWithdraw, child: const Text('Reject Job')),
              ),
            ] else if (job.myApplication!.status == JobApplicationStatus.rejected ||
                job.myApplication!.status == JobApplicationStatus.completed) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: onApply, child: const Text('Apply Again')),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(onPressed: onApply, child: const Text('Apply')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                ),
              ],
            ),
        ],
      ),
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
        // A bold, dark border clearly separates each job/requirement card
        // from the next — easier to tell listings apart at a glance than
        // the thin default outline used elsewhere.
        border: Border.all(color: AppColors.textPrimary, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(organisationJobDisplayId(requirement),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
          const SizedBox(height: AppSpacing.xs),
          _Tag(
            requirement.organisationType != null
                ? OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!
                : 'Organisation',
          ),
          const SizedBox(height: 2),
          Text(
            requirement.organisationName ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            _ApplicationTimeline(requirement.myApplication!),
            if (requirement.myApplication!.status == JobApplicationStatus.applied) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: onWithdraw, child: const Text('Reject Requirement')),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: onApply, child: const Text('Apply'))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('Reject'))),
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
      child: Text(label, style: const TextStyle(fontSize: 12)),
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
class _ApplicationTimeline extends StatefulWidget {
  final MyApplicationModel application;

  const _ApplicationTimeline(this.application);

  @override
  State<_ApplicationTimeline> createState() => _ApplicationTimelineState();
}

class _ApplicationTimelineState extends State<_ApplicationTimeline> {
  // Fixed per-row heights, rather than relying on inherited text-theme
  // metrics — the ambient DefaultTextStyle isn't stable enough to guess at
  // "roughly 3 lines" of pixels; picking a known font size and row height
  // instead makes the maxHeight below (and whether 3 rows actually
  // overflow it) exact instead of a fragile trial-and-error guess.
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
    // Every line names who did it — "you" for the caregiver's own actions
    // (apply/re-apply are never anyone else's), "employer" for whoever
    // posted the job/requirement deciding on it (admin, or the NurseNow
    // patient/organisation themselves — see decidedByAdmin below, which
    // despite the name covers both).
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
