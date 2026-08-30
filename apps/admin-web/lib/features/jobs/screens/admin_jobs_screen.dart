import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../organisation_requirements/data/admin_organisation_requirements_repository.dart';
import '../../organisation_requirements/widgets/requirement_widgets.dart';
import '../data/admin_jobs_repository.dart';
import '../widgets/job_detail_dialog.dart';
import '../widgets/job_read_only_detail_dialog.dart';

/// Admin posts a job built around the care receiver's needs, it's
/// broadcast to all caregivers via push, and caregivers apply/reject. This
/// screen covers post/list/close/view-applicants/accept-or-reject;
/// caregiver-facing browsing lives in apps/caregiver-app's Jobs tab.
///
/// A single "Jobs" tab also shows every NurseNow organisation (hospital/
/// clinic/rehab) requirement merged into the same list, sorted by post date
/// alongside admin/patient-posted jobs — the "Posted By" filter narrows to
/// one poster type at a time (or "All jobs"). organisation_requirements
/// stays a wholly separate table/model from jobs (see "NurseNow" in
/// CLAUDE.md); only the browse/list view is merged here, via the widgets
/// extracted into requirement_widgets.dart — creating/editing a job still
/// only ever produces a `jobs` row (admin never creates a requirement, the
/// org posts its own), and the two types keep their own dialogs.
class AdminJobsScreen extends ConsumerStatefulWidget {
  final JobsScreenInitialFilter? initialFilter;

  const AdminJobsScreen({super.key, this.initialFilter});

  @override
  ConsumerState<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

/// Pre-seeds the merged Jobs screen's filters to a single poster's
/// postings — passed as `/jobs`'s route argument by the "View Jobs" redirect
/// on a Rehab/Hospitals or Patients/Family row. [organisationType] set means
/// [postedByUserId] is an organisation account (scopes to the organisation-
/// requirements fetch only); left null means it's an individual account
/// (scopes to the jobs fetch only, via `posted_by_role=individual`). Every
/// other filter (search/city/status/etc.) stays available to narrow further
/// once landed — this only seeds the initial view, it doesn't lock anything.
class JobsScreenInitialFilter {
  final String postedByUserId;
  final String postedByLabel;
  final String? organisationType;

  const JobsScreenInitialFilter({
    required this.postedByUserId,
    required this.postedByLabel,
    this.organisationType,
  });
}

/// "Posted By" filter values narrowing the merged Jobs list to one poster
/// type. Hospital/Clinic/Rehab map to organisation_requirements.
/// organisation_type; Patients maps to jobs.posted_by_role='individual';
/// null (All jobs) fetches and merges both sources unfiltered by poster
/// type.
bool _isOrganisationPosterType(String? posterType) =>
    posterType == OrganisationType.hospital ||
    posterType == OrganisationType.clinic ||
    posterType == OrganisationType.rehab;

/// A single entry in the merged Jobs list — either a `jobs` row or an
/// organisation_requirements row, too different in shape to unify beyond
/// sharing a sort key. See _AdminJobsScreenState._mergedEntries.
sealed class _JobsListEntry {
  DateTime get postedAt;
}

class _JobEntry extends _JobsListEntry {
  final JobModel job;
  _JobEntry(this.job);

  @override
  DateTime get postedAt => DateTime.parse(job.postedAt);
}

class _RequirementEntry extends _JobsListEntry {
  final AdminOrganisationRequirement requirement;
  _RequirementEntry(this.requirement);

  @override
  DateTime get postedAt => DateTime.parse(requirement.postedAt);
}

class _AdminJobsScreenState extends ConsumerState<AdminJobsScreen> {
  List<JobModel> _jobs = [];
  List<AdminOrganisationRequirement> _requirements = [];
  bool _loading = true;
  String? _errorMessage;

  List<JobPosterOption> _posters = [];
  final _searchController = TextEditingController();
  String? _filterPostedBy;
  String? _filterOrgPostedBy;
  String? _filterPostedByLabel;
  String? _filterCity;
  String? _filterGender;
  String? _filterDutyType;
  String? _filterStatus;
  String? _filterLanguage;
  String? _filterPosterType;

  @override
  void initState() {
    super.initState();
    final initialFilter = widget.initialFilter;
    if (initialFilter != null) {
      _filterPostedByLabel = initialFilter.postedByLabel;
      if (initialFilter.organisationType != null) {
        _filterPosterType = initialFilter.organisationType;
        _filterOrgPostedBy = initialFilter.postedByUserId;
      } else {
        _filterPosterType = UserRole.individual;
        _filterPostedBy = initialFilter.postedByUserId;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadPosters();
    });
  }

  /// Clears only the single-poster narrowing from a "View Jobs" redirect —
  /// the broader "Posted By" poster-type selection (Hospital/Patients/etc.)
  /// stays as-is, so admin can widen back out to every posting of that type
  /// without losing the type filter entirely.
  void _clearSinglePosterFilter() {
    setState(() {
      _filterPostedBy = null;
      _filterOrgPostedBy = null;
      _filterPostedByLabel = null;
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Fetches whichever of the two poster-type-specific sources the "Posted
  /// By" filter calls for (both, when it's "All jobs") and merges them for
  /// display — see _mergedEntries. Job-only filters (Job Poster, Patient's
  /// Gender, Duty Time, Language) never apply to organisation requirements,
  /// so they're simply omitted from that fetch; Status/City/search apply to
  /// both, since organisation_requirements.status reuses the same 3-value
  /// enum and both tables carry a city.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final search = _searchController.text.trim().isEmpty
        ? null
        : _searchController.text.trim();
    final fetchJobs =
        _filterPosterType == null || _filterPosterType == UserRole.individual;
    final fetchRequirements = _filterPosterType == null ||
        _isOrganisationPosterType(_filterPosterType);
    try {
      final jobsFuture = fetchJobs
          ? ref.read(adminJobsRepositoryProvider).list(
                filters: JobListFilters(
                  postedBy: _filterPostedBy,
                  postedByRole: _filterPosterType == UserRole.individual
                      ? UserRole.individual
                      : null,
                  city: _filterCity,
                  gender: _filterGender,
                  dutyType: _filterDutyType,
                  status: _filterStatus,
                  language: _filterLanguage,
                  search: search,
                ),
              )
          : Future.value(<JobModel>[]);
      final requirementsFuture = fetchRequirements
          ? ref.read(adminOrganisationRequirementsRepositoryProvider).list(
                filters: OrganisationRequirementListFilters(
                  status: _filterStatus,
                  postedBy: _filterOrgPostedBy,
                  organisationType: _isOrganisationPosterType(_filterPosterType)
                      ? _filterPosterType
                      : null,
                  city: _filterCity,
                  search: search,
                ),
              )
          : Future.value(<AdminOrganisationRequirement>[]);
      final jobs = await jobsFuture;
      final requirements = await requirementsFuture;
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

  // Posters list is best-effort — a failure here shouldn't block the jobs
  // list itself from loading, so errors are swallowed (the dropdown just
  // stays empty rather than surfacing a second error banner).
  Future<void> _loadPosters() async {
    try {
      final posters = await ref.read(adminJobsRepositoryProvider).listPosters();
      if (mounted) setState(() => _posters = posters);
    } on ApiException catch (_) {
      // Swallowed — see comment above.
    }
  }

  void _applyFilters() => _load();

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      // A stray click outside the dialog must not silently wipe out
      // whatever the admin has already typed — only Cancel/Post do that.
      barrierDismissible: false,
      builder: (dialogContext) => const _JobFormDialog(),
    );
    if (created == true) await _load();
  }

  /// Opens the same form pre-filled with the job's full current details —
  /// doubles as "view full details" (every field is shown) and "edit"
  /// (fields are editable, Save Changes updates in place and reposts if
  /// the job was closed).
  Future<void> _openEditDialog(JobModel job) async {
    try {
      final (fullJob, _) =
          await ref.read(adminJobsRepositoryProvider).getDetail(job.id);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        // Same reasoning as the create dialog — don't let a stray outside
        // click discard in-progress edits.
        barrierDismissible: false,
        builder: (dialogContext) =>
            _JobFormDialog(job: fullJob, careReceiver: fullJob.careReceiver),
      );
      if (saved == true) await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Opened by tapping a job row — full detail, read-only, with an Edit
  /// button handing off to the existing _openEditDialog flow.
  Future<void> _openDetailDialog(JobModel job) async {
    try {
      final (fullJob, _) =
          await ref.read(adminJobsRepositoryProvider).getDetail(job.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => JobReadOnlyDetailDialog(
          job: fullJob,
          onEdit: () {
            Navigator.of(dialogContext).pop();
            _openEditDialog(job);
          },
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _close(JobModel job) async {
    try {
      await ref.read(adminJobsRepositoryProvider).close(job.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _remind(JobModel job) async {
    try {
      await ref.read(adminJobsRepositoryProvider).remind(job.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Reminder sent')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Only offered for a pending_review (NurseNow individual) requirement —
  /// declines it with a reason, which the individual sees on their own
  /// requirement view. It never goes live.
  Future<void> _reject(JobModel job) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject requirement'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Reason (shown to the requester)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(adminJobsRepositoryProvider)
          .reject(job.id, controller.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _viewApplications(JobModel job) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => JobDetailDialog(jobId: job.id),
    );
    await _load();
  }

  /// Doubles as "Approve" (from pending_review, sets frequency/salary/
  /// schedule for the first time) and "Edit" (from active/closed — admin
  /// can revisit/correct those same admin-set fields later; every other
  /// field stays org-owned, unchanged from [requirement]) — same dialog,
  /// same endpoint, only the label changes with current status.
  Future<void> _editRequirement(
      AdminOrganisationRequirement requirement) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => EditRequirementDialog(
        requirement: requirement,
        onSubmit: (frequency, salary, scheduleType, startDate, endDate,
            scheduleRepeat, specificDays) async {
          await ref
              .read(adminOrganisationRequirementsRepositoryProvider)
              .approve(
                requirement.id,
                typeOfNurse: requirement.typeOfNurse,
                frequencyOfCare: frequency,
                salaryAmount: salary,
                scheduleType: scheduleType,
                startDate: startDate,
                endDate: endDate,
                scheduleRepeat: scheduleRepeat,
                specificDays: specificDays,
                accommodationProvided: requirement.accommodationProvided,
                foodProvided: requirement.foodProvided,
                specialSkills: requirement.specialSkills,
              );
          await _load();
        },
      ),
    );
  }

  /// Only offered for a pending_review requirement — declines it with a
  /// reason, which the organisation sees on their own requirement view. It
  /// never goes live.
  Future<void> _rejectRequirement(
      AdminOrganisationRequirement requirement) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reject requirement'),
          content: TextField(
            controller: controller,
            maxLength: 1000,
            maxLines: 4,
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(
                labelText: 'Reason (shown to the organisation)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(adminOrganisationRequirementsRepositoryProvider)
          .reject(requirement.id, controller.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Row tap opens the full detail read-only; its own Edit button hands
  /// off to _editRequirement.
  Future<void> _viewRequirementDetail(
      AdminOrganisationRequirement requirement) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => RequirementReadOnlyDialog(
        requirement: requirement,
        onEdit: () {
          Navigator.of(dialogContext).pop();
          _editRequirement(requirement);
        },
      ),
    );
  }

  Future<void> _viewRequirementApplicants(
      AdminOrganisationRequirement requirement) async {
    final (_, applications) = await ref
        .read(adminOrganisationRequirementsRepositoryProvider)
        .getDetail(requirement.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => RequirementApplicantsDialog(
        requirement: requirement,
        applications: applications,
        onDecide: (applicationId, status) async {
          await ref
              .read(adminOrganisationRequirementsRepositoryProvider)
              .decideApplication(requirement.id, applicationId, status);
          await _load();
        },
      ),
    );
  }

  bool get _hasActiveFilters =>
      _filterPostedBy != null ||
      _filterOrgPostedBy != null ||
      _filterCity != null ||
      _filterGender != null ||
      _filterDutyType != null ||
      _filterStatus != null ||
      _filterLanguage != null ||
      _filterPosterType != null ||
      _searchController.text.trim().isNotEmpty;

  /// Both lists are unpaginated (limit 100 each), so they're simply merged
  /// and re-sorted client-side by post date, newest first — mirroring
  /// apps/caregiver-app's JobsScreen, which merges the same two sources the
  /// same way for caregiver-facing browsing.
  List<_JobsListEntry> get _mergedEntries {
    final entries = <_JobsListEntry>[
      ..._jobs.map(_JobEntry.new),
      ..._requirements.map(_RequirementEntry.new),
    ];
    entries.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return entries;
  }

  Widget _buildFilterPanel() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search job ID or patient ID (e.g. PAT-501)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _applyFilters(),
          ),
        ),
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            // Guarded against a value the dropdown doesn't itself list (e.g.
            // a patient's user id seeded by a "View Jobs" redirect, or any
            // organisation's, since _posters only ever lists admins) —
            // DropdownButtonFormField asserts its value matches exactly one
            // item, so an unmatched id must display as unselected here even
            // though it's still driving the actual fetch (see the "Filtered
            // to postings by" banner for that case).
            initialValue: _posters.any((p) => p.id == _filterPostedBy)
                ? _filterPostedBy
                : null,
            decoration: const InputDecoration(
                labelText: 'Job Poster',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All posters')),
              ..._posters.map(
                (p) => DropdownMenuItem<String?>(
                    value: p.id, child: Text('${p.fullName} (${p.phone})')),
              ),
            ],
            onChanged: (value) => setState(() => _filterPostedBy = value),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _filterPosterType,
            decoration: const InputDecoration(
                labelText: 'Posted By',
                border: OutlineInputBorder(),
                isDense: true),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('All jobs')),
              DropdownMenuItem<String?>(
                  value: OrganisationType.hospital, child: Text('Hospital')),
              DropdownMenuItem<String?>(
                  value: OrganisationType.clinic, child: Text('Clinic')),
              DropdownMenuItem<String?>(
                  value: OrganisationType.rehab, child: Text('Rehab')),
              DropdownMenuItem<String?>(
                  value: UserRole.individual, child: Text('Patients')),
            ],
            onChanged: (value) => setState(() => _filterPosterType = value),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _filterCity,
            decoration: const InputDecoration(
                labelText: 'City', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All cities')),
              ...City.all.map((c) => DropdownMenuItem<String?>(
                  value: c, child: Text(City.displayNames[c] ?? c))),
            ],
            onChanged: (value) => setState(() => _filterCity = value),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _filterGender,
            decoration: const InputDecoration(
              labelText: "Patient's Gender",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Any gender')),
              ...Gender.all.map((g) => DropdownMenuItem<String?>(
                  value: g, child: Text(Gender.displayNames[g] ?? g))),
            ],
            onChanged: (value) => setState(() => _filterGender = value),
          ),
        ),
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _filterDutyType,
            decoration: const InputDecoration(
                labelText: 'Duty Time',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All duty times')),
              ...DutyType.all.map((d) => DropdownMenuItem<String?>(
                  value: d, child: Text(DutyType.displayNames[d] ?? d))),
            ],
            onChanged: (value) => setState(() => _filterDutyType = value),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _filterStatus,
            decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All statuses')),
              ...JobStatus.all.map(
                (s) => DropdownMenuItem<String?>(
                    value: s, child: Text(JobStatus.displayNames[s] ?? s)),
              ),
            ],
            onChanged: (value) => setState(() => _filterStatus = value),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _filterLanguage,
            decoration: const InputDecoration(
                labelText: 'Language',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Any language')),
              ...Language.all.map(
                (l) => DropdownMenuItem<String?>(
                    value: l, child: Text(Language.displayNames[l] ?? l)),
              ),
            ],
            onChanged: (value) => setState(() => _filterLanguage = value),
          ),
        ),
        ElevatedButton(
            onPressed: _applyFilters, child: const Text('Apply Filters')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.jobs,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded + ellipsis so the button is never pushed off
                  // (and never forces a RenderFlex overflow) on a narrow
                  // viewport — "Jobs" never actually truncates in practice,
                  // this is purely a safety net for the layout.
                  const Expanded(
                    child: Text(
                      'Jobs',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton.icon(
                    onPressed: _openCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Post New Job'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildFilterPanel(),
              if (_filterPostedByLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _SinglePosterBanner(
                    label: _filterPostedByLabel!,
                    onClear: _clearSinglePosterFilter),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!,
                    style: const TextStyle(color: AppColors.error))
              else if (_mergedEntries.isEmpty)
                Text(
                  _hasActiveFilters
                      ? 'No jobs or requirements match these filters.'
                      : 'No jobs or requirements posted yet.',
                  style: const TextStyle(color: AppColors.textSecondary),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _mergedEntries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = _mergedEntries[index];
                      return switch (entry) {
                        _JobEntry(:final job) => _JobRow(
                            job: job,
                            onTap: () => _openDetailDialog(job),
                            onClose: job.status == JobStatus.active
                                ? () => _close(job)
                                : null,
                            onRemind: job.status == JobStatus.active
                                ? () => _remind(job)
                                : null,
                            onReject: job.status == JobStatus.pendingReview
                                ? () => _reject(job)
                                : null,
                            onViewApplications: () => _viewApplications(job),
                            onEdit: () => _openEditDialog(job),
                          ),
                        _RequirementEntry(:final requirement) => RequirementRow(
                            requirement: requirement,
                            onTap: () => _viewRequirementDetail(requirement),
                            onEdit: () => _editRequirement(requirement),
                            onReject:
                                requirement.status == JobStatus.pendingReview
                                    ? () => _rejectRequirement(requirement)
                                    : null,
                            onViewApplicants: () =>
                                _viewRequirementApplicants(requirement),
                          ),
                      };
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Salary's unit follows Frequency of Care — a 'daily' job's figure is a
/// per-day rate, everything else (including not-yet-picked) reads as
/// monthly, matching the pre-dynamic-unit default.
String _salaryUnit(String? frequencyOfCare) =>
    frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month';

class _JobRow extends StatelessWidget {
  final JobModel job;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final VoidCallback? onRemind;
  final VoidCallback? onReject;
  final VoidCallback onViewApplications;
  final VoidCallback onEdit;

  const _JobRow({
    required this.job,
    required this.onTap,
    required this.onClose,
    required this.onRemind,
    required this.onReject,
    required this.onViewApplications,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          jobDisplayId(job),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                '${DutyType.displayNames[job.dutyType] ?? job.dutyType} · '
                '${City.displayNames[job.city] ?? job.city}',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _JobStatusBadge(status: job.status),
          ],
        ),
        if (job.postedByRole == UserRole.individual) ...[
          const SizedBox(height: 2),
          Text(
            'Posted by patient/family${job.postedByName != null ? ' — ${job.postedByName}' : ''}',
            style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            border: Border.all(color: AppColors.success),
          ),
          child: Text(
            job.salaryAmount != null
                ? '₹${job.salaryAmount}/${_salaryUnit(job.frequencyOfCare)}'
                : 'Salary not set',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: job.salaryAmount != null
                  ? AppColors.success
                  : AppColors.error,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            if (job.area != null && job.area!.isNotEmpty) job.area,
            job.languages.isEmpty
                ? _noPreferenceLanguageLabel
                : job.languages.map((l) => Language.displayNames[l] ?? l).join(', '),
          ].join(' • '),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Posted: ${_formatDate(DateTime.parse(job.postedAt))}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (job.description != null && job.description!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(job.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );

    final actions = Wrap(
      spacing: AppSpacing.xs,
      children: [
        TextButton(onPressed: onEdit, child: const Text('Edit')),
        TextButton(
            onPressed: onViewApplications, child: const Text('Applicants')),
        if (onRemind != null)
          TextButton(onPressed: onRemind, child: const Text('Remind')),
        if (onClose != null)
          TextButton(onPressed: onClose, child: const Text('Close')),
        if (onReject != null)
          TextButton(onPressed: onReject, child: const Text('Reject')),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          // Below the mobile breakpoint the action buttons no longer
          // reliably fit beside the content column (a Row's non-flexible
          // children don't wrap on their own) — stack them below instead.
          // Above it, the existing side-by-side layout has always had
          // enough room.
          child: context.isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    content,
                    const SizedBox(height: AppSpacing.sm),
                    actions
                  ],
                )
              : Row(
                  children: [Expanded(child: content), actions],
                ),
        ),
      ),
    );
  }
}

const Map<String, String> _jobStatusLabels = {
  JobStatus.pendingReview: 'Pending Review',
  JobStatus.active: 'Active',
  JobStatus.closed: 'Closed',
};

const Map<String, Color> _jobStatusColors = {
  JobStatus.pendingReview: Colors.orange,
  JobStatus.active: AppColors.success,
  JobStatus.closed: AppColors.textSecondary,
};

/// Job's own status (active/closed/pending_review) — distinct from
/// VitaStatusBadge, which is specifically for a caregiver's
/// VerificationStatus and doesn't know about job statuses.
class _JobStatusBadge extends StatelessWidget {
  final String status;

  const _JobStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _jobStatusColors[status] ?? AppColors.textSecondary;
    final label = _jobStatusLabels[status] ?? status;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Shown when a "View Jobs" redirect from a single Rehab/Hospitals or
/// Patients/Family row has narrowed the list to that one poster's postings
/// — every other filter still applies on top, this just says which single
/// account is currently in scope and offers a way back to the broader view.
class _SinglePosterBanner extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const _SinglePosterBanner({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Showing postings by: $label',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: AppSpacing.xs),
          InkWell(
            onTap: onClear,
            child: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Sentinel for "No Preference" on Language Preference — mirrors
/// nursenow-app's Post/Edit Requirement screens exactly, so admin's own
/// create/edit form can represent (and preserve, when approving/editing a
/// patient's posting) the exact same choice a patient made, never forcing
/// a language selection that wasn't actually chosen. An empty array is
/// sent to the server either way — see create-job.dto.ts.
const _noPreferenceLanguage = 'no_preference';
const _noPreferenceLanguageLabel = 'No Preference';

/// Handles both posting a new job and editing an existing one. Pass [job] +
/// [careReceiver] to open pre-filled in edit mode (same dialog doubles as
/// the "view full details" surface, since every field is visible); leave
/// both null to post a brand new job.
class _JobFormDialog extends ConsumerStatefulWidget {
  final JobModel? job;
  final CareReceiverModel? careReceiver;

  const _JobFormDialog({this.job, this.careReceiver});

  @override
  ConsumerState<_JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends ConsumerState<_JobFormDialog> {
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _medicalConditionOtherController = TextEditingController();
  final _toiletAssistanceOtherController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _salaryController = TextEditingController();

  // Only mandatory text fields need a FocusNode — that's what lets Post
  // literally put the cursor in the first one that's missing.
  final _areaFocusNode = FocusNode();
  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _salaryFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();

  // One key per mandatory field, in the order they appear on the form, so
  // Post can scroll to whichever one is first still-invalid.
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _medicalConditionsKey = GlobalKey();
  final _vitalMonitoringTypesKey = GlobalKey();
  final _salaryKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _frequencyKey = GlobalKey();
  final _startDateKey = GlobalKey();
  final _languagesKey = GlobalKey();
  final _descriptionKey = GlobalKey();

  // Only turns true once Post has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  // Job Location
  String? _city;

  // About Patient
  String? _gender;
  String? _communication;
  String? _feedingType;
  bool _hasMedicalCondition = false;
  List<String> _medicalConditions = [];
  List<String> _toiletAssistance = [];
  bool _requiresVitalMonitoring = false;
  List<String> _vitalMonitoringTypes = [];

  // Duty
  String? _dutyType;
  String? _frequencyOfCare;
  DateTime? _startDate;

  List<String> _languages = [_noPreferenceLanguage];
  String? _preferredGender; // null = no preference
  String? _preferredReligion; // null = no preference

  bool _submitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.job != null;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    final cr = widget.careReceiver;
    if (job != null && cr != null) {
      _city = job.city;
      _areaController.text = job.area ?? '';
      _descriptionController.text = job.description ?? '';
      _dutyType = job.dutyType;
      _frequencyOfCare = job.frequencyOfCare;
      _startDate =
          job.startDate == null ? null : DateTime.tryParse(job.startDate!);
      _languages =
          job.languages.isEmpty ? [_noPreferenceLanguage] : List.of(job.languages);
      _salaryController.text = job.salaryAmount?.toString() ?? '';
      _preferredGender = job.preferredGender;
      _preferredReligion = job.preferredReligion;

      _ageController.text = cr.age.toString();
      _gender = cr.gender;
      _weightController.text = cr.weightKg.toString();
      _communication = cr.communication;
      _feedingType = cr.feedingType;
      _hasMedicalCondition = cr.hasMedicalCondition;
      _medicalConditions = List.of(cr.medicalConditions);
      _medicalConditionOtherController.text = cr.medicalConditionOther ?? '';
      _toiletAssistance = List.of(cr.toiletAssistance);
      _toiletAssistanceOtherController.text = cr.toiletAssistanceOther ?? '';
      _requiresVitalMonitoring = cr.requiresVitalMonitoring;
      _vitalMonitoringTypes = List.of(cr.vitalMonitoringTypes);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _areaController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _salaryController.dispose();
    _areaFocusNode.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _salaryFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());
  int? get _salaryAmount => int.tryParse(_salaryController.text.trim());

  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid =>
      _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isMedicalConditionsValid =>
      !_hasMedicalCondition || _medicalConditions.isNotEmpty;
  bool get _isVitalMonitoringTypesValid =>
      !_requiresVitalMonitoring || _vitalMonitoringTypes.isNotEmpty;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isFrequencyValid => _frequencyOfCare != null;
  bool get _isSalaryValid =>
      _salaryAmount != null && _salaryAmount! >= 1 && _salaryAmount! <= 1000000;
  bool get _isStartDateValid => _startDate != null;

  /// What actually gets sent to the server — the sentinel is purely a
  /// client-side selection aid, never a real language value (see
  /// create-job.dto.ts: an empty array is how "No Preference" is
  /// represented on the wire, same as individual/NurseNow postings).
  List<String> get _effectiveLanguages =>
      _languages.contains(_noPreferenceLanguage) ? [] : _languages;

  bool get _canSubmit =>
      !_submitting &&
      _isCityValid &&
      _isAreaValid &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isMedicalConditionsValid &&
      _isVitalMonitoringTypesValid &&
      _isDutyTypeValid &&
      _isFrequencyValid &&
      _isStartDateValid &&
      _isSalaryValid;

  /// In on-form order, so the first invalid one found here is genuinely
  /// the first one the admin sees when Post scrolls them to it.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid,
            focusNode: _weightFocusNode),
        _MandatoryField(_medicalConditionsKey, _isMedicalConditionsValid),
        _MandatoryField(_vitalMonitoringTypesKey, _isVitalMonitoringTypesValid),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_frequencyKey, _isFrequencyValid),
        _MandatoryField(_salaryKey, _isSalaryValid,
            focusNode: _salaryFocusNode),
        _MandatoryField(_startDateKey, _isStartDateValid),
      ];

  /// Mirrors nursenow-app's Post/Edit Requirement screens exactly: picking
  /// a real language drops "No Preference"; picking "No Preference" clears
  /// any real selections; deselecting the only remaining real language
  /// falls back to "No Preference" rather than leaving the field empty.
  void _applyLanguageSelection(List<String> next) {
    final added = next.where((l) => !_languages.contains(l));
    final removed = _languages.where((l) => !next.contains(l));
    if (added.contains(_noPreferenceLanguage)) {
      _languages
        ..clear()
        ..add(_noPreferenceLanguage);
    } else if (added.isNotEmpty) {
      _languages
        ..clear()
        ..addAll(next.where((l) => l != _noPreferenceLanguage));
    } else if (removed.isNotEmpty) {
      final remaining = next.where((l) => l != _noPreferenceLanguage).toList();
      _languages
        ..clear()
        ..addAll(remaining.isEmpty ? [_noPreferenceLanguage] : remaining);
    }
  }

  /// Post is always clickable — this is what runs when it's tapped. With
  /// something missing, it flags every missing mandatory field red and
  /// jumps straight to the first one instead of submitting.
  Future<void> _handlePostPressed() async {
    if (_submitting) return;
    if (!_canSubmit) {
      setState(() => _showValidationErrors = true);
      _MandatoryField? firstInvalid;
      for (final field in _mandatoryFieldsInOrder) {
        if (!field.isValid) {
          firstInvalid = field;
          break;
        }
      }
      if (firstInvalid != null) {
        final target = firstInvalid;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = target.key.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
          target.focusNode?.requestFocus();
        });
      }
      return;
    }
    await _submit();
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final careReceiver = CareReceiverInput(
        age: _age!,
        gender: _gender!,
        weightKg: _weightKg!,
        communication: _communication,
        feedingType: _feedingType,
        hasMedicalCondition: _hasMedicalCondition,
        medicalConditions: _hasMedicalCondition ? _medicalConditions : null,
        medicalConditionOther:
            _medicalConditions.contains(MedicalCondition.other) &&
                    _medicalConditionOtherController.text.trim().isNotEmpty
                ? _medicalConditionOtherController.text.trim()
                : null,
        toiletAssistance: _toiletAssistance,
        toiletAssistanceOther:
            _toiletAssistance.contains(ToiletAssistance.others) &&
                    _toiletAssistanceOtherController.text.trim().isNotEmpty
                ? _toiletAssistanceOtherController.text.trim()
                : null,
        requiresVitalMonitoring: _requiresVitalMonitoring,
        vitalMonitoringTypes:
            _requiresVitalMonitoring ? _vitalMonitoringTypes : null,
      );
      final startDate = _startDate == null
          ? null
          : '${_startDate!.year.toString().padLeft(4, '0')}-'
              '${_startDate!.month.toString().padLeft(2, '0')}-'
              '${_startDate!.day.toString().padLeft(2, '0')}';

      if (_isEditing) {
        await ref.read(adminJobsRepositoryProvider).update(
              widget.job!.id,
              careReceiver: careReceiver,
              city: _city!,
              area: _areaController.text.trim(),
              description: _descriptionController.text.trim(),
              dutyType: _dutyType!,
              frequencyOfCare: _frequencyOfCare!,
              startDate: startDate,
              languages: _effectiveLanguages,
              salaryAmount: _salaryAmount!,
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
            );
      } else {
        await ref.read(adminJobsRepositoryProvider).create(
              careReceiver: careReceiver,
              city: _city!,
              area: _areaController.text.trim(),
              description: _descriptionController.text.trim(),
              dutyType: _dutyType!,
              frequencyOfCare: _frequencyOfCare!,
              startDate: startDate,
              languages: _effectiveLanguages,
              salaryAmount: _salaryAmount!,
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          _isEditing ? 'Edit ${jobDisplayId(widget.job!)}' : 'Post New Job'),
      content: SizedBox(
        width: context.dialogWidth(480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Job Location',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _cityKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _city,
                  decoration: InputDecoration(
                    labelText: 'City (Mandatory)',
                    errorText: _showValidationErrors && !_isCityValid
                        ? 'Please select a city'
                        : null,
                  ),
                  items: City.all
                      .map((c) => DropdownMenuItem(
                          value: c, child: Text(City.displayNames[c] ?? c)))
                      .toList(),
                  onChanged: (value) => setState(() => _city = value),
                ),
              ),
              if (_city != null) ...[
                const SizedBox(height: AppSpacing.sm),
                KeyedSubtree(
                  key: _areaKey,
                  child: TextField(
                    controller: _areaController,
                    focusNode: _areaFocusNode,
                    decoration: InputDecoration(
                      labelText:
                          'Area in ${City.displayNames[_city] ?? _city} (Mandatory)',
                      errorText: _showValidationErrors && !_isAreaValid
                          ? 'Area is required'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('About Patient',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _ageKey,
                child: TextField(
                  controller: _ageController,
                  focusNode: _ageFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Patient's Age (Mandatory)",
                    errorText: _showValidationErrors && !_isAgeValid
                        ? 'Age is required (1-120)'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _genderKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _gender,
                  decoration: InputDecoration(
                    labelText: "Patient's Gender (Mandatory)",
                    errorText: _showValidationErrors && !_isGenderValid
                        ? 'Please select a gender'
                        : null,
                  ),
                  items: const [
                    DropdownMenuItem(value: Gender.male, child: Text('Male')),
                    DropdownMenuItem(
                        value: Gender.female, child: Text('Female')),
                    DropdownMenuItem(value: Gender.other, child: Text('Other')),
                  ],
                  onChanged: (value) => setState(() => _gender = value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _weightKey,
                child: TextField(
                  controller: _weightController,
                  focusNode: _weightFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Patient's Weight (kg) (Mandatory)",
                    errorText: _showValidationErrors && !_isWeightValid
                        ? 'Weight is required (1-300 kg)'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _communication,
                decoration: const InputDecoration(labelText: 'Communication'),
                items: Communication.all
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(Communication.displayNames[c] ?? c)))
                    .toList(),
                onChanged: (value) => setState(() => _communication = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _feedingType,
                decoration: const InputDecoration(labelText: 'Feeding'),
                items: FeedingType.all
                    .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(FeedingType.displayNames[f] ?? f)))
                    .toList(),
                onChanged: (value) => setState(() => _feedingType = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Has a medical condition the caregiver should know about?'),
                value: _hasMedicalCondition,
                onChanged: (value) => setState(() {
                  _hasMedicalCondition = value;
                  if (!value) _medicalConditions = [];
                }),
              ),
              if (_hasMedicalCondition) ...[
                KeyedSubtree(
                  key: _medicalConditionsKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Condition(s) (Mandatory)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _showValidationErrors &&
                                  !_isMedicalConditionsValid
                              ? AppColors.error
                              : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      VitaMultiSelectChips(
                        options: MedicalCondition.all,
                        labels: MedicalCondition.displayNames,
                        selected: _medicalConditions,
                        onChanged: (next) =>
                            setState(() => _medicalConditions = next),
                      ),
                      if (_showValidationErrors && !_isMedicalConditionsValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Select at least one condition',
                            style:
                                TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      if (_medicalConditions
                          .contains(MedicalCondition.other)) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _medicalConditionOtherController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Please describe the other condition'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text('Toilet Assistance',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Text(
                'What assistance is required? Select all that apply.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.xs),
              VitaMultiSelectChips(
                options: ToiletAssistance.all,
                labels: ToiletAssistance.displayNames,
                selected: _toiletAssistance,
                onChanged: (next) => setState(() => _toiletAssistance = next),
              ),
              if (_toiletAssistance.contains(ToiletAssistance.others)) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _toiletAssistanceOtherController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Please describe the other toilet assistance'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Is regular vital monitoring required?'),
                value: _requiresVitalMonitoring,
                onChanged: (value) => setState(() {
                  _requiresVitalMonitoring = value;
                  if (!value) _vitalMonitoringTypes = [];
                }),
              ),
              if (_requiresVitalMonitoring) ...[
                KeyedSubtree(
                  key: _vitalMonitoringTypesKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select what needs monitoring (Mandatory)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _showValidationErrors &&
                                  !_isVitalMonitoringTypesValid
                              ? AppColors.error
                              : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      VitaMultiSelectChips(
                        options: VitalMonitoringType.all,
                        labels: VitalMonitoringType.displayNames,
                        selected: _vitalMonitoringTypes,
                        onChanged: (next) =>
                            setState(() => _vitalMonitoringTypes = next),
                      ),
                      if (_showValidationErrors &&
                          !_isVitalMonitoringTypesValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Select at least one vital to monitor',
                            style:
                                TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('About Nurse/Caregiver Requirement',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _dutyTypeKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _dutyType,
                  decoration: InputDecoration(
                    labelText: 'Hours Care Needed (Mandatory)',
                    errorText: _showValidationErrors && !_isDutyTypeValid
                        ? 'Please select duty hours'
                        : null,
                  ),
                  items: DutyType.all
                      .map((d) => DropdownMenuItem(
                          value: d, child: Text(DutyType.displayNames[d] ?? d)))
                      .toList(),
                  onChanged: (value) => setState(() => _dutyType = value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _frequencyKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _frequencyOfCare,
                  decoration: InputDecoration(
                    labelText: 'Frequency of Care (Mandatory)',
                    errorText: _showValidationErrors && !_isFrequencyValid
                        ? 'Please select a frequency'
                        : null,
                  ),
                  items: FrequencyOfCare.all
                      .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(FrequencyOfCare.displayNames[f] ?? f)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _frequencyOfCare = value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Below Frequency of Care so the unit shown in this field's own
              // label logically follows the field the admin just picked.
              KeyedSubtree(
                key: _salaryKey,
                child: TextField(
                  controller: _salaryController,
                  focusNode: _salaryFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Salary (₹/${_salaryUnit(_frequencyOfCare)}) (Mandatory)',
                    errorText: _showValidationErrors && !_isSalaryValid
                        ? 'Salary is required'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _startDateKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A persistent heading, unlike the old design where the
                    // button's own label doubled as the display text — that
                    // meant "Preferred Start Date" disappeared the moment a
                    // date was picked, leaving just a bare date with no
                    // context for what it was.
                    Text(
                      'Preferred Start Date (Mandatory)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _showValidationErrors && !_isStartDateValid
                            ? AppColors.error
                            : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    OutlinedButton(
                      onPressed: _pickStartDate,
                      child: Text(
                        _startDate == null
                            ? 'Select date'
                            : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                    if (_showValidationErrors && !_isStartDateValid)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Please select a start date',
                          style:
                              TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _languagesKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Language Preference',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    VitaMultiSelectChips(
                      options: [_noPreferenceLanguage, ...Language.all],
                      labels: {
                        _noPreferenceLanguage: _noPreferenceLanguageLabel,
                        ...Language.displayNames,
                      },
                      selected: _languages,
                      onChanged: (next) =>
                          setState(() => _applyLanguageSelection(next)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _preferredGender,
                decoration: const InputDecoration(
                    labelText: 'Preferred Caregiver Gender'),
                items: const [
                  DropdownMenuItem<String?>(
                      value: null, child: Text('No preference')),
                  DropdownMenuItem<String?>(
                      value: Gender.male, child: Text('Male')),
                  DropdownMenuItem<String?>(
                      value: Gender.female, child: Text('Female')),
                ],
                onChanged: (value) => setState(() => _preferredGender = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _preferredReligion,
                decoration: const InputDecoration(
                    labelText: 'Preferred Caregiver Religion'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('No preference')),
                  // "Others" is excluded — a valid caregiver's own religion
                  // at registration, but not offered as a job preference.
                  ...Religion.all.where((r) => r != Religion.others).map(
                        (r) => DropdownMenuItem<String?>(
                            value: r,
                            child: Text(Religion.displayNames[r] ?? r)),
                      ),
                ],
                onChanged: (value) =>
                    setState(() => _preferredReligion = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              KeyedSubtree(
                key: _descriptionKey,
                child: TextField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocusNode,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'More details you want to share about patient',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_errorMessage!,
                    style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        ElevatedButton(
          // Always clickable — missing fields are handled inside
          // _handlePostPressed (highlight + scroll), not by disabling this.
          onPressed: _submitting ? null : _handlePostPressed,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEditing ? 'Save Changes' : 'Post'),
        ),
      ],
    );
  }
}
