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

const _kCategoryOptions = <(String value, String label)>[
  (_kHomeCareCategory, 'Home Care Jobs'),
  (OrganisationType.hospital, 'Hospital Jobs'),
  (OrganisationType.clinic, 'Clinic Jobs'),
  (OrganisationType.rehab, 'Rehab Jobs'),
  (OrganisationType.agency, 'Agency Jobs'),
];

/// "Find Jobs" — jobs/requirements the caregiver has NOT applied to yet
/// (plus a collapsed "marked not interested" section for ones they
/// declined). Once applied, a listing moves to the My Jobs tab (Applied
/// sub-tab) and stops appearing here at all — this is a deliberate IA
/// split from the single merged browse+track list this screen used to be:
/// "where do I find new work" and "where do I track what I've already
/// gone for" are now two different places, matching the My Jobs/Find Jobs
/// split in the reference design. Every status/terminology here is still
/// exactly what CLAUDE.md documents (applied/rejected/accepted/completed,
/// decided_by_admin, applied_at) — only the screen layout changed, not
/// what the backend tracks.
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
  // Defaults off — matches the reference design's "Show N jobs you marked
  // not interested" collapsed link at the bottom of the list.
  bool _showNotInterested = false;
  String? _categoryFilter;
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

  Future<bool> _applyToJob(JobModel job, String status) async {
    setState(() => _applyingId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).applyToJob(job.id, status);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (mounted) showVitaErrorBanner(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _applyingId.remove(job.id));
    }
  }

  Future<bool> _applyToRequirement(OrganisationRequirementModel requirement, String status) async {
    setState(() => _applyingId.add(requirement.id));
    try {
      await ref.read(organisationOpeningsRepositoryProvider).apply(requirement.id, status);
      await _load();
      return true;
    } on ApiException catch (e) {
      if (mounted) showVitaErrorBanner(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _applyingId.remove(requirement.id));
    }
  }

  /// "Not interested" — a plain, pre-apply decline (lands on the existing
  /// `rejected` status, same as before; only the button's own label
  /// changed). Still confirms first, since it's not reversible on its own
  /// (re-applying is always possible afterward, same as today).
  Future<bool> _notInterested(JobModel job) async {
    if (!await _confirmNotInterested(jobDisplayId(job))) return false;
    return _applyToJob(job, JobApplicationStatus.rejected);
  }

  Future<bool> _confirmNotInterested(String displayId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Not interested in this job?'),
        content: Text('You can still change your mind and apply to $displayId later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Not Interested'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  List<_Listing> _mergedListings() {
    final listings = <_Listing>[
      ..._jobs.map(_JobListing.new),
      ..._requirements.map(_RequirementListing.new),
    ];
    listings.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return listings;
  }

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
    // Three buckets, mutually exclusive: never applied (shown up front),
    // not interested / rejected (collapsed), and applied/accepted/
    // completed (not shown here at all — see My Jobs). The "applications"
    // summary counts below are deliberately computed from the full
    // `merged` list, not `filtered` — a caregiver's own application
    // counts shouldn't change just because they're filtering the browse
    // list by city/category.
    final neverApplied = filtered.where((l) => l.myApplicationStatus == null).toList();
    final notInterested = filtered.where((l) => l.myApplicationStatus == JobApplicationStatus.rejected).toList();
    final waitingCount = merged.where((l) => l.myApplicationStatus == JobApplicationStatus.applied).length;
    final selectedCount = merged.where((l) => l.myApplicationStatus == JobApplicationStatus.accepted).length;

    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('Find Jobs'),
        actions: caregiverAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            if (waitingCount > 0 || selectedCount > 0) _ApplicationsSummaryBar(waiting: waitingCount, selected: selectedCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
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
                            child: Text(City.displayNames[city] ?? city, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                        children: [
                          if (_errorMessage != null)
                            Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
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
                          else ...[
                            Text(
                              '${neverApplied.length} open job${neverApplied.length == 1 ? '' : 's'} you have not applied to',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (neverApplied.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                                child: Text(
                                  "You've already applied to (or marked not interested) every open job. "
                                  'Check My Jobs, or pull down to refresh.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            for (final listing in neverApplied) ...[
                              _buildCard(listing, notInterestedMode: false),
                              const SizedBox(height: AppSpacing.md),
                            ],
                          ],
                          if (notInterested.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            InkWell(
                              onTap: () => setState(() => _showNotInterested = !_showNotInterested),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _showNotInterested
                                          ? 'Hide jobs you marked not interested'
                                          : 'Show ${notInterested.length} job${notInterested.length == 1 ? '' : 's'} you marked not interested',
                                      style: const TextStyle(
                                          color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: AppTypography.small),
                                    ),
                                    Icon(
                                      _showNotInterested ? Icons.expand_less : Icons.expand_more,
                                      color: AppColors.primary,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showNotInterested)
                              for (final listing in notInterested) ...[
                                _buildCard(listing, notInterestedMode: true),
                                const SizedBox(height: AppSpacing.md),
                              ],
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

  Widget _buildCard(_Listing listing, {required bool notInterestedMode}) {
    if (listing is _JobListing) {
      return _JobCard(
        job: listing.job,
        isApplying: _applyingId.contains(listing.job.id),
        notInterestedMode: notInterestedMode,
        onApply: () => _applyToJob(listing.job, JobApplicationStatus.applied),
        onNotInterested: () => _notInterested(listing.job),
      );
    }
    final requirement = (listing as _RequirementListing).requirement;
    return _RequirementCard(
      requirement: requirement,
      isApplying: _applyingId.contains(requirement.id),
      notInterestedMode: notInterestedMode,
      onApply: () => _applyToRequirement(requirement, JobApplicationStatus.applied),
    );
  }
}

/// "Your applications: N waiting · N selected" + a jump link to My Jobs —
/// mirrors the reference design's summary bar exactly. Counts are a plain
/// read of existing MyApplicationModel.status values, nothing new.
class _ApplicationsSummaryBar extends StatelessWidget {
  final int waiting;
  final int selected;

  const _ApplicationsSummaryBar({required this.waiting, required this.selected});

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (waiting > 0) '$waiting waiting',
      if (selected > 0) '$selected selected',
    ];
    return Container(
      width: double.infinity,
      color: AppColors.primaryLight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Your applications: ${parts.join(' · ')}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.small),
            ),
          ),
          InkWell(
            onTap: () => Navigator.of(context).pushReplacementNamed('/caregiver/my-jobs'),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'My Jobs',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: AppTypography.small),
                ),
                Icon(Icons.chevron_right, color: AppColors.primary, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Common shape the merged list sorts/filters by.
abstract class _Listing {
  DateTime get postedAt;
  String get id;
  /// Null if the caregiver has never applied — the only three real values
  /// this ever takes here are null/applied/rejected, since an
  /// accepted/completed listing has already moved to My Jobs (this screen
  /// only ever fetches ACTIVE postings, and an accepted one closes
  /// immediately — see JobModel docs).
  String? get myApplicationStatus;
}

class _JobListing extends _Listing {
  final JobModel job;
  _JobListing(this.job);
  @override
  String get id => job.id;
  @override
  DateTime get postedAt => DateTime.parse(job.postedAt);
  @override
  String? get myApplicationStatus => job.myApplication?.status;
}

class _RequirementListing extends _Listing {
  final OrganisationRequirementModel requirement;
  _RequirementListing(this.requirement);
  @override
  String get id => requirement.id;
  @override
  DateTime get postedAt => DateTime.parse(requirement.postedAt);
  @override
  String? get myApplicationStatus => requirement.myApplication?.status;
}

class _JobCard extends StatelessWidget {
  final JobModel job;
  final bool isApplying;
  final bool notInterestedMode;
  final VoidCallback onApply;
  final VoidCallback onNotInterested;

  const _JobCard({
    required this.job,
    required this.isApplying,
    required this.notInterestedMode,
    required this.onApply,
    required this.onNotInterested,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: notInterestedMode ? AppColors.textSecondary : AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobDetailCard(job: job),
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (notInterestedMode)
            SizedBox(
              width: double.infinity,
              child: _ApplyButton(onPressed: onApply, label: 'View and apply'),
            )
          else
            Row(
              children: [
                Expanded(child: _ApplyButton(onPressed: onApply, label: 'View and apply')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _NotInterestedButton(onPressed: onNotInterested)),
              ],
            ),
        ],
      ),
    );
  }
}

class _ApplyButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const _ApplyButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      icon: const Icon(Icons.check, size: 18),
      label: Text(label),
    );
  }
}

class _NotInterestedButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NotInterestedButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.textSecondary),
      ),
      child: const Text('Not interested'),
    );
  }
}

/// Unlike a regular job, an organisation requirement offers no "Not
/// interested" option at all — a caregiver can only apply, never decline
/// outright (pre-existing, unchanged behavior, requested explicitly for
/// the organisation flow — see CLAUDE.md's "NurseNow" section).
class _RequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final bool isApplying;
  final bool notInterestedMode;
  final VoidCallback onApply;

  const _RequirementCard({
    required this.requirement,
    required this.isApplying,
    required this.notInterestedMode,
    required this.onApply,
  });

  String get _typeOfNurseText => requirement.typeOfNurse == TypeOfNurse.others && requirement.typeOfNurseOther != null
      ? requirement.typeOfNurseOther!
      : TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: notInterestedMode ? AppColors.textSecondary : AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              Tag(requirement.accommodationProvided ? 'Accommodation provided' : 'No accommodation'),
              Tag(requirement.foodProvided ? 'Food provided' : 'No food'),
              Tag('Vacancies: ${requirement.numberOfVacancies}'),
              if (requirement.durationType != null)
                Tag(RequirementDuration.displayNames[requirement.durationType] ?? requirement.durationType!),
              Tag(
                'Preferred Gender: ${requirement.preferredGender != null ? (Gender.displayNames[requirement.preferredGender] ?? requirement.preferredGender!) : 'No Preference'}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
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
                    style: TextStyle(fontSize: AppTypography.small, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
                Icon(Icons.open_in_full, size: 15, color: AppColors.primary),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else
            SizedBox(width: double.infinity, child: _ApplyButton(onPressed: onApply, label: 'View and apply')),
        ],
      ),
    );
  }
}

