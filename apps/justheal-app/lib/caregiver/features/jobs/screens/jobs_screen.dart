import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/messages_bell.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../widgets/job_detail_card.dart';

/// Sentinel category value for a plain admin/individual-posted job (the
/// `jobs` table) — distinct from every `OrganisationType` value, which
/// cover the 4 organisation-posted requirement categories instead.
const _kHomeCareCategory = 'home_care';

/// One dropdown option per posting category — "Home Care" (a regular job)
/// plus every OrganisationType value (an organisation requirement of that
/// type). Order matches how the user asked for them.
const _kCategoryOptions = <(String value, String label)>[
  (_kHomeCareCategory, 'Home Care Jobs'),
  (OrganisationType.hospital, 'Hospital Jobs'),
  (OrganisationType.clinic, 'Clinic Jobs'),
  (OrganisationType.rehab, 'Rehab Jobs'),
  (OrganisationType.agency, 'Agency Jobs'),
];

/// Unified list of active postings — admin/individual jobs AND organisation
/// (hospital/rehab/clinic/agency) requirements shown together, sorted by
/// post date. Organisation requirements previously lived on their own
/// separate "Openings" tab; merged into one Jobs section on explicit
/// request so a caregiver only has to check one place. Applying is gated
/// server-side (JOB_001 for jobs, the same eligibility rule for
/// requirements) to available/assigned caregivers only; a caregiver in any
/// other status sees the server's rejection message when they try, rather
/// than the buttons being hidden entirely.
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
  // Defaults off — a job/requirement the caregiver is done with (rejected
  // by either side, or closed themselves after being accepted — see
  // _Listing.isHiddenByDefault) is hidden by default to keep the list
  // focused on what's still open to them. One tap away to see everything.
  bool _showAllJobs = false;
  // Which single posting category to include — a plain client-side filter
  // over the already-fetched lists, no new endpoint. null means every
  // category shown, matching the same "nothing selected = show everything"
  // convention as _cityFilter below.
  String? _categoryFilter;
  // null means every city.
  String? _cityFilter;

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

  /// Returns whether the call actually succeeded — callers that need to
  /// react to that (e.g. closing a dialog only once the underlying action
  /// really went through, not on every tap regardless of outcome) can
  /// await this instead of assuming success.
  Future<bool> _applyToJob(JobModel job, String status) async {
    setState(() => _applyingId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).applyToJob(job.id, status);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _applyingId.remove(job.id));
    }
  }

  /// Returns whether the call actually succeeded — same contract as
  /// [_applyToJob].
  Future<bool> _applyToRequirement(OrganisationRequirementModel requirement, String status) async {
    setState(() => _applyingId.add(requirement.id));
    try {
      await ref.read(organisationOpeningsRepositoryProvider).apply(requirement.id, status);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _applyingId.remove(requirement.id));
    }
  }

  /// A plain, pre-apply decline — the caregiver has never applied to this
  /// job at all, they're just saying no from the browse list. Every reject
  /// action needs a confirmation first (see [_withdrawJob], the other path
  /// that lands on the same 'rejected' status), so this always shows the
  /// dialog before calling through to [_applyToJob]. Returns whether it
  /// actually went through (false if cancelled at the confirmation step or
  /// if the server call itself failed).
  Future<bool> _rejectJob(JobModel job) async {
    if (!await _confirmReject(jobDisplayId(job))) return false;
    return _applyToJob(job, JobApplicationStatus.rejected);
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
  /// patient's view of this application. Returns whether it actually went
  /// through (false if cancelled or the server call failed) — see
  /// [_rejectJob]'s own doc comment.
  Future<bool> _withdrawJob(JobModel job) async {
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
    if (confirmed != true) return false;
    return _applyToJob(job, JobApplicationStatus.rejected);
  }

  /// Opens a job's or requirement's full, unmodified card (same widget
  /// shown for every other status) in a scrollable dialog — used by
  /// [_AppliedStub] so a collapsed "already applied" card still gives full
  /// access to everything the full card offers, including the Reject Job
  /// (withdraw) button for a plain job, without duplicating any of that
  /// widget's own logic. [cardBuilder] gets the dialog's own
  /// [BuildContext] so its action callbacks (e.g. onWithdraw) can pop this
  /// dialog themselves once the action actually succeeds — this dialog's
  /// content is otherwise a static snapshot that never refreshes itself,
  /// so without this an action taken inside it would silently update the
  /// list behind it while leaving a stale copy on screen. The explicit
  /// close button below is the fallback for every other case (cancelling,
  /// or just being done looking).
  Future<void> _showFullJobCard(BuildContext context, WidgetBuilder cardBuilder) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Always-visible close button — tapping an action inside the
              // card (e.g. Reject Job) updates the browse list behind this
              // dialog but, since this dialog's own content is a static
              // snapshot taken when it opened, never closes itself or
              // refreshes its own now-stale copy. This is the explicit way
              // out, rather than relying on tapping outside the dialog.
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                  child: cardBuilder(dialogContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_Listing> _mergedListings() {
    final listings = <_Listing>[
      ..._jobs.map(_JobListing.new),
      ..._requirements.map(_RequirementListing.new),
    ];
    listings.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return listings;
  }

  /// A plain job is always "Home Care"; an organisation requirement's own
  /// category is its `organisationType` (hospital/clinic/rehab/agency).
  String? _categoryOf(_Listing listing) => listing is _JobListing
      ? _kHomeCareCategory
      : (listing as _RequirementListing).requirement.organisationType;

  String? _cityOf(_Listing listing) =>
      listing is _JobListing ? listing.job.city : (listing as _RequirementListing).requirement.city;

  bool _matchesFilters(_Listing listing) {
    if (_categoryFilter != null && _categoryOf(listing) != _categoryFilter) return false;
    if (_cityFilter != null && _cityOf(listing) != _cityFilter) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final merged = _mergedListings();
    final filtered = merged.where(_matchesFilters).toList();
    final hasHiddenJobs = filtered.any((l) => l.isHiddenByDefault);
    final visible = _showAllJobs ? filtered : filtered.where((l) => !l.isHiddenByDefault).toList();
    final mostRecentlyAppliedId = _mostRecentlyAppliedListingId(visible);
    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('Jobs'),
        // Logout lives only on the Profile screen now (moved to the bottom
        // of the page there) — no longer duplicated in every screen's
        // AppBar.
        actions: caregiverAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            // Pinned above the scrollable list, not inside it — these
            // filters must stay visible while scrolling through jobs, not
            // scroll away with the rest of the content.
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              // Both filters sit in one row, never wrapping to a second
              // line — Job Type takes the remaining space (its labels are
              // the longest text on the row), City stays a small
              // fixed-width dropdown since a city name is short.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: _categoryFilter,
                      decoration: const InputDecoration(
                        labelText: 'Job Type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Jobs', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        for (final option in _kCategoryOptions)
                          DropdownMenuItem<String?>(
                            value: option.$1,
                            child: Text(option.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) => setState(() => _categoryFilter = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: _cityFilter,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        for (final city in City.all)
                          DropdownMenuItem<String?>(
                            value: city,
                            child: Text(
                              City.displayNames[city] ?? city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _cityFilter = value),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const Center(child: VitaLoadingIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                        children: [
                          if (_errorMessage != null)
                            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                          if (hasHiddenJobs)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Show All Jobs'),
                              subtitle: const Text(
                                'Includes jobs and organisation requirements you rejected, or closed yourself',
                              ),
                              value: _showAllJobs,
                              onChanged: (value) => setState(() => _showAllJobs = value),
                            ),
                          if (merged.isEmpty && _errorMessage == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                              child: Text(
                                'No jobs posted right now. Pull down to refresh.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          else if (filtered.isEmpty && _errorMessage == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                              child: Text(
                                'No jobs match your current filters. Try adjusting them.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          else if (visible.isEmpty && _errorMessage == null)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                              child: Text(
                                'No jobs you can currently apply to. Turn on "Show All Jobs" to see jobs and '
                                'organisation requirements you rejected or closed yourself.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ),
                          for (final listing in visible) ...[
                            if (listing is _JobListing)
                              if (listing.job.myApplication?.status == JobApplicationStatus.applied &&
                                  listing.id != mostRecentlyAppliedId)
                                _AppliedStub(
                                  displayId: jobDisplayId(listing.job),
                                  onTap: () => _showFullJobCard(
                                    context,
                                    (dialogContext) => _JobCard(
                                      job: listing.job,
                                      isApplying: _applyingId.contains(listing.job.id),
                                      onApply: () async {
                                        final success =
                                            await _applyToJob(listing.job, JobApplicationStatus.applied);
                                        if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                                      },
                                      onReject: () async {
                                        final success = await _rejectJob(listing.job);
                                        if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                                      },
                                      onWithdraw: () async {
                                        final success = await _withdrawJob(listing.job);
                                        if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                                      },
                                    ),
                                  ),
                                )
                              else
                                _JobCard(
                                  job: listing.job,
                                  isApplying: _applyingId.contains(listing.job.id),
                                  onApply: () => _applyToJob(listing.job, JobApplicationStatus.applied),
                                  onReject: () => _rejectJob(listing.job),
                                  onWithdraw: () => _withdrawJob(listing.job),
                                )
                            else if (listing is _RequirementListing)
                              if (listing.requirement.myApplication?.status == JobApplicationStatus.applied &&
                                  listing.id != mostRecentlyAppliedId)
                                _AppliedStub(
                                  displayId: organisationJobDisplayId(listing.requirement),
                                  onTap: () => _showFullJobCard(
                                    context,
                                    (dialogContext) => _RequirementCard(
                                      requirement: listing.requirement,
                                      isApplying: _applyingId.contains(listing.requirement.id),
                                      onApply: () async {
                                        final success = await _applyToRequirement(
                                            listing.requirement, JobApplicationStatus.applied);
                                        if (success && dialogContext.mounted) Navigator.of(dialogContext).pop();
                                      },
                                    ),
                                  ),
                                )
                              else
                                _RequirementCard(
                                  requirement: listing.requirement,
                                  isApplying: _applyingId.contains(listing.requirement.id),
                                  onApply: () =>
                                      _applyToRequirement(listing.requirement, JobApplicationStatus.applied),
                                ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                      ),
              ),
            ),
          ],
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

  /// Stable id, used to compare a listing against itself across rebuilds
  /// (e.g. "is this the most recently applied one") without caring
  /// whether it's a job or a requirement underneath.
  String get id;

  /// True once this listing is done from the caregiver's own point of
  /// view and there's nothing further they can do about it. Hides once
  /// rejected (by either side, or by closing/withdrawing themselves before
  /// being accepted) or closed themselves after being accepted
  /// (`completed`) — the job/requirement reopens to active for everyone
  /// else, but this caregiver's own engagement with it is over. Applies
  /// equally to jobs and organisation requirements.
  bool get isHiddenByDefault;

  /// When the caregiver's own still-`applied` application was last acted
  /// on — re-applying counts as more recent than the original apply, same
  /// as everywhere else "applied" is timestamped in this app. Null unless
  /// the application is currently `applied` (not applied at all, or
  /// already decided/withdrawn) — only listings with a real value here are
  /// candidates for "most recently applied" treatment (see
  /// _mostRecentlyAppliedListingId below).
  DateTime? get appliedAt;
}

class _JobListing extends _Listing {
  final JobModel job;
  _JobListing(this.job);
  @override
  String get id => job.id;
  @override
  DateTime get postedAt => DateTime.parse(job.postedAt);
  // Hidden by default once the caregiver rejected it (by either side) or
  // closed it themselves after being accepted (`completed`) — same rule as
  // _RequirementListing below. The job itself stays active either way (a
  // rejected/completed application on it can always be re-applied to, see
  // _JobCard's "Apply Again" button), it's just tucked out of the default
  // view until "Show All Jobs" is switched on.
  @override
  bool get isHiddenByDefault =>
      job.myApplication?.status == JobApplicationStatus.rejected ||
      job.myApplication?.status == JobApplicationStatus.completed;
  @override
  DateTime? get appliedAt => _appliedAtOf(job.myApplication);
}

class _RequirementListing extends _Listing {
  final OrganisationRequirementModel requirement;
  _RequirementListing(this.requirement);
  @override
  String get id => requirement.id;
  @override
  DateTime get postedAt => DateTime.parse(requirement.postedAt);
  @override
  bool get isHiddenByDefault =>
      requirement.myApplication?.status == JobApplicationStatus.rejected ||
      requirement.myApplication?.status == JobApplicationStatus.completed;
  @override
  DateTime? get appliedAt => _appliedAtOf(requirement.myApplication);
}

DateTime? _appliedAtOf(MyApplicationModel? application) {
  if (application == null || application.status != JobApplicationStatus.applied) return null;
  final raw = application.reappliedAt ?? application.appliedAt;
  return raw == null ? null : DateTime.parse(raw);
}

/// Among every listing the caregiver is currently waiting on a decision
/// for, finds the single most recently applied (or re-applied) one — null
/// if none are currently applied. Used so that one still stands out as a
/// full [_JobCard]/[_RequirementCard] rather than collapsing into
/// [_AppliedStub] with the rest: a caregiver who just applied to something
/// should still see it in full immediately, while older pending
/// applications they're already waiting on get tucked away.
String? _mostRecentlyAppliedListingId(List<_Listing> listings) {
  String? bestId;
  DateTime? bestTime;
  for (final listing in listings) {
    final appliedAt = listing.appliedAt;
    if (appliedAt == null) continue;
    if (bestTime == null || appliedAt.isAfter(bestTime)) {
      bestTime = appliedAt;
      bestId = listing.id;
    }
  }
  return bestId;
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
    // The single most-recently-applied job stays at full size (see
    // _mostRecentlyAppliedListingId) rather than collapsing into
    // _AppliedStub like older applied ones — but it used to keep the exact
    // same red "live job" border as a brand-new, not-yet-applied job, so
    // scanning the list gave no visual cue it had already been acted on; a
    // caregiver had to scroll to the bottom of the card to find out. Green
    // (same color _ApplyButton itself uses) plus an explicit badge gives
    // the same "already handled" signal _AppliedStub's grey stamp gives
    // the older applied ones, without it getting demoted to a tiny stub.
    final applied = job.myApplication?.status == JobApplicationStatus.applied;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: applied ? AppColors.success : AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (applied) ...[
            const _AppliedBadge(),
            const SizedBox(height: AppSpacing.sm),
          ],
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

/// Collapsed stand-in for [_JobCard]/[_RequirementCard] once the caregiver
/// has applied and is still waiting on a decision — a browse list full of
/// already-applied postings at full size pushed everything the caregiver
/// could still act on further down the screen, so this shrinks each one
/// down to a single greyed-out row with a diagonal "Applied" stamp.
/// Applies identically to a plain job and an organisation requirement —
/// [displayId] is the only thing that differs between the two call sites.
/// Tapping it opens the exact same, unmodified full card (including the
/// Reject Job/withdraw button, for a plain job) in a dialog via
/// [_showFullJobCard] — nothing about that card's own behavior changes,
/// only how it's reached while collapsed.
class _AppliedStub extends StatelessWidget {
  final String displayId;
  final VoidCallback onTap;

  const _AppliedStub({required this.displayId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Container(
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.4), width: 1.5),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayId,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: AppTypography.small,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
                  ],
                ),
              ),
              IgnorePointer(
                child: Transform.rotate(
                  angle: -0.35,
                  child: Text(
                    'APPLIED',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w900,
                      fontSize: AppTypography.heading,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small solid-green pill shown at the top of the single still-full-size
/// _JobCard/_RequirementCard once the caregiver has applied — see the
/// comment on _JobCard.build for why this exists alongside _AppliedStub
/// rather than relying on the border color change alone.
class _AppliedBadge extends StatelessWidget {
  const _AppliedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.white, size: 16),
          SizedBox(width: AppSpacing.xs),
          Text(
            'You Applied — Waiting for Decision',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: AppTypography.small),
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

/// Unlike a regular job, an organisation requirement offers no Reject
/// option at all — a caregiver can only Apply, never decline outright or
/// withdraw afterward. This is a deliberate difference from _JobCard,
/// requested explicitly for the organisation flow.
class _RequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final bool isApplying;
  final VoidCallback onApply;

  const _RequirementCard({
    required this.requirement,
    required this.isApplying,
    required this.onApply,
  });

  /// The plain "Type of Nurse/Caregiver Needed" text as filled on nursenow's
  /// own posting form — free text when 'others', else the enum's display
  /// name. Shared by the header line and the type-of-nurse tag below it.
  String get _typeOfNurseText => requirement.typeOfNurse == TypeOfNurse.others && requirement.typeOfNurseOther != null
      ? requirement.typeOfNurseOther!
      : TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse;

  @override
  Widget build(BuildContext context) {
    // See the matching comment in _JobCard.build — same "give the
    // still-full-size, most-recently-applied card a distinct color/badge"
    // fix, applied identically here.
    final applied = requirement.myApplication?.status == JobApplicationStatus.applied;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: applied ? AppColors.success : AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (applied) ...[
            const _AppliedBadge(),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            'Job Posted by Organisation'
            '${requirement.city != null ? ' in ${City.displayNames[requirement.city] ?? requirement.city!}' : ''}'
            ' · $_typeOfNurseText',
            style: const TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.bold, color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: organisationJobDisplayId(requirement),
                  style: const TextStyle(
                      fontSize: AppTypography.small, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                ),
                // Only present on the browse list (GET /caregiver/organisation-requirements)
                // — null on the assigned/MyJobs list, where this doesn't apply.
                if (requirement.applicantCount != null)
                  TextSpan(
                    text: '  ·  ${requirement.applicantCount} applied',
                    style: const TextStyle(
                        fontSize: AppTypography.small, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
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
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _Tag(requirement.accommodationProvided ? 'Accommodation provided' : 'No accommodation'),
              _Tag(requirement.foodProvided ? 'Food provided' : 'No food'),
              _Tag('Vacancies: ${requirement.numberOfVacancies}'),
              if (requirement.durationType != null)
                _Tag(RequirementDuration.displayNames[requirement.durationType] ?? requirement.durationType!),
              // Always shown, even when there's no preference — never a
              // blank gap. Spelled out as "Preferred Gender" (not just
              // "Preferred"), so it's unambiguous which preference this is.
              _Tag(
                'Preferred Gender: ${requirement.preferredGender != null ? (Gender.displayNames[requirement.preferredGender] ?? requirement.preferredGender!) : 'No Preference'}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Pushes a dedicated full-screen page rather than expanding inline
          // — Special Skills can be a genuinely long free-text block, same
          // reasoning as JobDetailCard's own "View Full Details" link.
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RequirementFullDetailScreen(requirement: requirement)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'View Full Details',
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
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (requirement.myApplication != null)
            ApplicationTimeline(requirement.myApplication!)
          else
            SizedBox(width: double.infinity, child: _ApplyButton(onPressed: onApply, label: 'Apply')),
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
