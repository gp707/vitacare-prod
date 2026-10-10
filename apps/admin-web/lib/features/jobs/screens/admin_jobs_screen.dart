import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../organisation_requirements/data/admin_organisation_requirements_repository.dart';
import '../../organisation_requirements/widgets/requirement_widgets.dart';
import '../data/admin_jobs_repository.dart';
import '../widgets/job_detail_dialog.dart';
import '../widgets/job_read_only_detail_dialog.dart';

/// Admin posts a job built around the care receiver's needs, it's
/// broadcast to all caregivers via push, and caregivers apply/reject. This
/// screen covers post/list/close/view-applicants/accept-or-reject;
/// caregiver-facing browsing lives in apps/justheal-app's (lib/caregiver) Jobs tab.
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

/// Pre-seeds the merged Jobs screen's filters — passed as `/jobs`'s route
/// argument either by the "View Jobs" redirect on a Rehab/Hospitals or
/// Patients/Family row ([postedByUserId] set), or by the Dashboard's "Needs
/// Approval" tile ([status] set, no poster narrowing at all). [organisationType]
/// set means [postedByUserId] is an organisation account (scopes to the
/// organisation-requirements fetch only); [postedByUserId] set with
/// [organisationType] left null means it's an individual account (scopes to
/// the jobs fetch only, via `posted_by_role=individual`). Every other filter
/// (search/city/status/etc.) stays available to narrow further once landed —
/// this only seeds the initial view, it doesn't lock anything.
class JobsScreenInitialFilter {
  final String? postedByUserId;
  final String? postedByLabel;
  final String? organisationType;
  final String? status;

  const JobsScreenInitialFilter({
    this.postedByUserId,
    this.postedByLabel,
    this.organisationType,
    this.status,
  });
}

/// "Posted By" filter values narrowing the merged Jobs list to one poster
/// type. Hospital/Clinic/Rehab map to organisation_requirements.
/// organisation_type; Patients maps to jobs.posted_by_role='individual';
/// null (All jobs) fetches and merges both sources unfiltered by poster
/// type.
bool _isOrganisationPosterType(String? posterType) => OrganisationType.all.contains(posterType);

/// A single entry in the merged Jobs list — either a `jobs` row or an
/// organisation_requirements row, too different in shape to unify beyond
/// sharing a sort key. See _AdminJobsScreenState._mergedEntries.
sealed class _JobsListEntry {
  DateTime get postedAt;
  _SelectionKey get selectionKey;
  String get displayId;
}

class _JobEntry extends _JobsListEntry {
  final JobModel job;
  _JobEntry(this.job);

  @override
  DateTime get postedAt => DateTime.parse(job.postedAt);

  @override
  _SelectionKey get selectionKey => _SelectionKey(id: job.id, type: 'job');

  @override
  String get displayId => jobDisplayId(job);
}

class _RequirementEntry extends _JobsListEntry {
  final AdminOrganisationRequirement requirement;
  _RequirementEntry(this.requirement);

  @override
  DateTime get postedAt => DateTime.parse(requirement.postedAt);

  @override
  _SelectionKey get selectionKey => _SelectionKey(id: requirement.id, type: 'organisation_requirement');

  @override
  String get displayId => requirementDisplayId(requirement);
}

/// Identifies one selected row for bulk delete — [type] matches
/// BulkDeleteItem's own 'job'/'organisation_requirement' values exactly,
/// since a selection is sent to the server as-is.
class _SelectionKey {
  final String id;
  final String type;

  const _SelectionKey({required this.id, required this.type});

  @override
  bool operator ==(Object other) => other is _SelectionKey && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}

class _AdminJobsScreenState extends ConsumerState<AdminJobsScreen> {
  List<JobModel> _jobs = [];
  List<AdminOrganisationRequirement> _requirements = [];
  bool _loading = true;
  String? _errorMessage;

  // Super-admin-only permanent bulk delete — see AdminBulkDeleteService.
  // Both _jobs and _requirements are already unpaginated single fetches
  // (limit 100 each, see JobListFilters.toQueryParameters), so "Select All
  // Matching Filters" is simply every row currently loaded — there's no
  // separate multi-page traversal to do.
  final Set<_SelectionKey> _selected = {};
  bool _bulkDeleting = false;

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
  // Empty means "no filter" — matches every other optional filter here
  // (defaults to null/unselected), so the list isn't silently narrowed on
  // first load. Admin types a number (e.g. 3, matching
  // Validation.applyByWindowDays) to find jobs that have fallen out of
  // their caregiver-facing apply-by urgency window.
  final _staleDaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initialFilter = widget.initialFilter;
    if (initialFilter != null) {
      _filterStatus = initialFilter.status;
      if (initialFilter.postedByUserId != null) {
        _filterPostedByLabel = initialFilter.postedByLabel;
        if (initialFilter.organisationType != null) {
          _filterPosterType = initialFilter.organisationType;
          _filterOrgPostedBy = initialFilter.postedByUserId;
        } else {
          _filterPosterType = UserRole.individual;
          _filterPostedBy = initialFilter.postedByUserId;
        }
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
    _staleDaysController.dispose();
    super.dispose();
  }

  int? get _filterPostedMoreThanDaysAgo => int.tryParse(_staleDaysController.text.trim());

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
      // A reload (initial load, filter change, or post-delete refresh)
      // always invalidates whatever was previously selected — the list
      // it referred to is about to change.
      _selected.clear();
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
                  postedMoreThanDaysAgo: _filterPostedMoreThanDaysAgo,
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
  /// goes live as-is, no edit required. The same legitimacy-review
  /// activation saving an unchanged edit from pending_review already
  /// performs, just a direct one-click action.
  Future<void> _approve(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve requirement'),
        content: const Text(
          'This requirement will go live immediately and every caregiver will be notified. Continue?',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminJobsRepositoryProvider).approve(job.id);
      await _load();
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
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm'),
          ),
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

  /// Always offered, any status — admin can edit any org-owned field;
  /// saving from pending_review (or closed) also approves/reposts it.
  Future<void> _editRequirement(AdminOrganisationRequirement requirement) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => EditRequirementDialog(
        requirement: requirement,
        onSubmit: ({
          required typeOfNurse,
          typeOfNurseOther,
          required accommodationProvided,
          required foodProvided,
          specialSkills,
          required numberOfVacancies,
          preferredGender,
          required durationType,
        }) async {
          await ref.read(adminOrganisationRequirementsRepositoryProvider).edit(
                requirement.id,
                typeOfNurse: typeOfNurse,
                typeOfNurseOther: typeOfNurseOther,
                accommodationProvided: accommodationProvided,
                foodProvided: foodProvided,
                specialSkills: specialSkills,
                numberOfVacancies: numberOfVacancies,
                preferredGender: preferredGender,
                durationType: durationType,
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
            TextButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Confirm'),
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

  /// Row tap opens the full detail read-only; its own Edit button (always
  /// offered, any status) hands off to _editRequirement.
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
      _filterPostedMoreThanDaysAgo != null ||
      _searchController.text.trim().isNotEmpty;

  /// Both lists are unpaginated (limit 100 each), so they're simply merged
  /// and re-sorted client-side by post date, newest first — mirroring
  /// apps/justheal-app's (lib/caregiver) JobsScreen, which merges the same two sources the
  /// same way for caregiver-facing browsing.
  List<_JobsListEntry> get _mergedEntries {
    final entries = <_JobsListEntry>[
      ..._jobs.map(_JobEntry.new),
      ..._requirements.map(_RequirementEntry.new),
    ];
    entries.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return entries;
  }

  void _toggleSelected(_SelectionKey key, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    });
  }

  /// Selects every row currently loaded — already exactly "every row
  /// matching the current filters" (see _mergedEntries's own note on the
  /// two sources being unpaginated single fetches), so this needs no
  /// separate page-by-page traversal.
  void _selectAllMatchingFilters() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_mergedEntries.map((entry) => entry.selectionKey));
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _confirmAndBulkDelete() async {
    final selectedEntries =
        _mergedEntries.where((entry) => _selected.contains(entry.selectionKey)).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _BulkDeleteConfirmDialog(
        count: selectedEntries.length,
        sampleDisplayIds: selectedEntries.take(5).map((entry) => entry.displayId).toList(),
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkDeleting = true);
    try {
      final result = await ref.read(adminJobsRepositoryProvider).bulkDelete(
            selectedEntries.map((entry) => BulkDeleteItem(id: entry.selectionKey.id, type: entry.selectionKey.type)).toList(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permanently deleted ${result.jobsDeleted + result.requirementsDeleted} posting(s) '
              'and ${result.applicationsDeleted} application(s).',
            ),
          ),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
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
              prefixIcon: Icon(Icons.search),
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
                prefixIcon: Icon(Icons.person_outline),
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
                prefixIcon: Icon(Icons.source),
                labelText: 'Posted By',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All jobs')),
              ...OrganisationType.all.map((t) => DropdownMenuItem<String?>(
                  value: t, child: Text(OrganisationType.displayNames[t] ?? t))),
              const DropdownMenuItem<String?>(
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
                prefixIcon: Icon(Icons.location_city),
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
              prefixIcon: Icon(Icons.wc),
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
                prefixIcon: Icon(Icons.access_time),
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
                prefixIcon: Icon(Icons.flag_outlined),
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
                prefixIcon: Icon(Icons.language),
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
        SizedBox(
          width: 220,
          child: TextField(
            controller: _staleDaysController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.hourglass_bottom),
                labelText: 'Posted more than __ days ago',
                hintText: 'e.g. ${Validation.applyByWindowDays}',
                border: OutlineInputBorder(),
                isDense: true),
            onSubmitted: (_) => _applyFilters(),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _applyFilters,
          icon: const Icon(Icons.filter_alt, size: 18),
          label: const Text('Apply Filters'),
        ),
      ],
    );
  }

  /// Super-admin-only — a regular admin token would 403 on the endpoint
  /// itself, so the bar isn't even shown to avoid offering an action that
  /// can't succeed. Hidden entirely (not just disabled) when there's
  /// nothing loaded to select.
  Widget _buildBulkActionsBar() {
    final session = ref.watch(sessionProvider);
    final isSuperAdmin = session is AdminSessionAuthenticated && session.isSuperAdmin;
    if (!isSuperAdmin || _mergedEntries.isEmpty) return const SizedBox.shrink();

    final allSelected = _selected.length == _mergedEntries.length;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: allSelected ? _clearSelection : _selectAllMatchingFilters,
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 18),
            label: Text(
              allSelected ? 'Clear Selection' : 'Select All ${_mergedEntries.length} Matching Filters',
            ),
          ),
          if (_selected.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _bulkDeleting ? null : _confirmAndBulkDelete,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              icon: _bulkDeleting
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_forever, size: 18),
              label: Text('Delete Selected (${_selected.length})'),
            ),
        ],
      ),
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
                          TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold),
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
              _buildBulkActionsBar(),
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
                      final row = switch (entry) {
                        _JobEntry(:final job) => _JobRow(
                            job: job,
                            onTap: () => _openDetailDialog(job),
                            onClose: job.status == JobStatus.active
                                ? () => _close(job)
                                : null,
                            onRemind: job.status == JobStatus.active
                                ? () => _remind(job)
                                : null,
                            onApprove: job.status == JobStatus.pendingReview
                                ? () => _approve(job)
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
                      final session = ref.watch(sessionProvider);
                      final isSuperAdmin =
                          session is AdminSessionAuthenticated && session.isSuperAdmin;
                      if (!isSuperAdmin) return row;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _selected.contains(entry.selectionKey),
                            onChanged: (checked) => _toggleSelected(entry.selectionKey, checked),
                          ),
                          Expanded(child: row),
                        ],
                      );
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
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback onViewApplications;
  final VoidCallback onEdit;

  const _JobRow({
    required this.job,
    required this.onTap,
    required this.onClose,
    required this.onRemind,
    required this.onApprove,
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
            fontSize: AppTypography.small,
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
        if (job.postedByRole != null) ...[
          const SizedBox(height: 2),
          _PosterLine(
            label: job.postedByRole == UserRole.individual ? 'Posted by patient/family' : 'Posted by Admin',
            name: job.postedByName,
            phone: job.postedByPhone,
            // Only a patient/family poster has a profile screen to link to
            // — there's no equivalent detail screen for an admin account.
            onTap: job.postedByRole == UserRole.individual
                ? () => Navigator.of(context).pushNamed('/individual-detail', arguments: job.postedBy)
                : null,
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
              fontSize: AppTypography.small,
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
          style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Posted: ${_formatDate(DateTime.parse(job.postedAt))}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
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
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Edit'),
        ),
        TextButton.icon(
          onPressed: onViewApplications,
          icon: const Icon(Icons.people_outline, size: 16),
          label: const Text('Applicants'),
        ),
        if (onRemind != null)
          TextButton.icon(
            onPressed: onRemind,
            icon: const Icon(Icons.notifications_active_outlined, size: 16),
            label: const Text('Remind'),
          ),
        if (onClose != null)
          TextButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Close'),
          ),
        if (onApprove != null)
          TextButton.icon(
            onPressed: onApprove,
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Approve'),
          ),
        if (onReject != null)
          TextButton.icon(
            onPressed: onReject,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Reject'),
          ),
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

/// Renders "Posted by {role} — {name} · {phone}", optionally tappable when
/// [onTap] is provided (i.e. there's an actual profile screen to open —
/// an admin poster has none). Nested inside a row that's itself already
/// wrapped in its own InkWell (open the read-only detail dialog), so this
/// is its own InkWell rather than a plain GestureDetector, matching how
/// the row's action buttons already coexist with the outer tap target.
class _PosterLine extends StatelessWidget {
  final String label;
  final String? name;
  final String? phone;
  final VoidCallback? onTap;

  const _PosterLine({required this.label, this.name, this.phone, this.onTap});

  @override
  Widget build(BuildContext context) {
    final labelAndName = name != null ? '$label — $name' : label;
    final text = Text(
      phone != null ? '$labelAndName · $phone' : labelAndName,
      style: TextStyle(
        color: AppColors.primaryDark,
        fontSize: AppTypography.small,
        fontWeight: FontWeight.w600,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );
    if (onTap == null) return text;
    return InkWell(onTap: onTap, child: text);
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
              color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600)),
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

/// Sentinel for "None" on Medical Condition — mirrors nursenow-app's
/// Post/Edit Requirement screens exactly: mandatory, always-visible
/// multi-select, mutually exclusive with every real condition, never a
/// toggle-then-reveal. Translated to `has_medical_condition: false` (no
/// `medical_conditions`) at submission time.
const _noneMedicalCondition = 'none';
const _noneMedicalConditionLabel = 'None';

/// Handles both posting a new job and editing an existing one. Pass [job] +
/// [careReceiver] to open pre-filled in edit mode (same dialog doubles as
/// the "view full details" surface, since every field is visible); leave
/// both null to post a brand new job.
///
/// Field set and order are unified with nursenow-app's own Post/Edit
/// Requirement screens exactly — Patient Details / Care Preferences / Nurse
/// Fee Guidance — for every job admin creates or edits, whether it's
/// admin's own from-scratch posting or approving/editing a NurseNow
/// individual's own requirement. There is no longer a field-set branch
/// between the two cases. Vital Monitoring and the free-text "more details"
/// description field are not offered here at all (removed entirely from
/// this form — the backend still defaults/accepts them server-side).
/// Communication has been removed from the product entirely (see its own
/// enum entry in CLAUDE.md) — no field, no default, nowhere shown.
/// Frequency of Care is always
/// derived from Duration Care is Needed (never a manual dropdown) and
/// Salary is always a freely-editable, Rate-Card-suggested figure — no
/// manual-entry path remains for either.
class _JobFormDialog extends ConsumerStatefulWidget {
  final JobModel? job;
  final CareReceiverModel? careReceiver;

  const _JobFormDialog({this.job, this.careReceiver});

  @override
  ConsumerState<_JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends ConsumerState<_JobFormDialog> {
  final _patientNameController = TextEditingController();
  final _areaController = TextEditingController();
  final _medicalConditionOtherController = TextEditingController();
  final _toiletAssistanceOtherController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _salaryController = TextEditingController();

  // Only mandatory text fields need a FocusNode — that's what lets Post
  // literally put the cursor in the first one that's missing.
  final _patientNameFocusNode = FocusNode();
  final _areaFocusNode = FocusNode();
  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _salaryFocusNode = FocusNode();

  // One key per mandatory field, in the order they appear on the form, so
  // Post can scroll to whichever one is first still-invalid.
  final _patientNameKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _salaryKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _startDateKey = GlobalKey();
  final _careDurationKey = GlobalKey();
  final _toiletAssistanceKey = GlobalKey();
  final _feedingTypeKey = GlobalKey();

  // Only turns true once Post has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  // Patient Details
  String? _city;
  String? _gender;
  // Defaults to "None" — a real, deliberate choice, not an unset field (see
  // _noneMedicalCondition above). Mandatory: always holds at least one
  // value, so it can never be truly empty.
  List<String> _medicalConditions = [_noneMedicalCondition];

  // Care Preferences
  String? _feedingType;
  List<String> _toiletAssistance = [];
  String? _dutyType;
  DateTime? _startDate;
  String? _careDuration;
  List<String> _languages = [_noPreferenceLanguage];
  String? _preferredGender; // null = no preference
  String? _preferredReligion; // null = no preference

  // Nurse Fee Guidance — Frequency of Care is always derived from
  // _careDuration (see _derivedFrequencyOfCare); Salary is suggested from
  // the Rate Card but freely editable, refreshed reactively as related
  // fields change (see _refreshSuggestedSalary).
  List<RateCardModel> _rateCards = const [];
  // Tracks the last suggestion auto-filled into _salaryController, so a
  // relevant field change can safely refresh it — but only while admin
  // hasn't typed something of their own over it yet.
  String? _lastAutoSuggestedSalary;

  bool _submitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.job != null;

  /// Few Days/Few Weeks price off the daily Rate Card, Few Months/Long Term
  /// off the monthly one — see [frequencyForCareDuration].
  String? get _derivedFrequencyOfCare =>
      _careDuration == null ? null : frequencyForCareDuration(_careDuration!);

  /// Rebuilds a [CareReceiverModel] from whatever's currently live-edited
  /// on this dialog, for [deriveCareTier] — mirrors nursenow-app's own
  /// Post/Edit Requirement screens exactly. Vital-monitoring isn't
  /// collected on this form at all, so it's fixed at its server-side
  /// default, same as nursenow-app's PostRequirementScreen.
  CareReceiverModel get _careReceiverForTierDerivation => CareReceiverModel(
        id: widget.careReceiver?.id ?? '',
        age: _age ?? 0,
        gender: _gender ?? '',
        weightKg: _weightKg ?? 0,
        feedingType: _feedingType ?? FeedingType.oralFeeding,
        hasMedicalCondition: !_medicalConditions.contains(_noneMedicalCondition),
        medicalConditions:
            _medicalConditions.contains(_noneMedicalCondition) ? const [] : _medicalConditions,
        toiletAssistance: _toiletAssistance,
        requiresVitalMonitoring: false,
        vitalMonitoringTypes: const [],
      );

  /// Fire-and-forget, called once from initState — fetches the Rate Card,
  /// then applies its suggestion the same *guarded* way [_refreshSuggestedSalary]
  /// always has: only into an empty field, never overwriting a pre-filled
  /// existing job's salary_amount. Deliberately NOT the unconditional-
  /// overwrite-on-load behavior nursenow-app's own EditRequirementScreen
  /// uses for the patient's own posting — here, admin approving/editing a
  /// job that already carries a real salary (set by the NurseNow patient
  /// themselves, or a previous admin edit) must never have it silently
  /// replaced the moment the Rate Card resolves. On a brand-new job (Salary
  /// field starts empty) this still fills in the initial suggestion exactly
  /// as before. Fails open: a network error, or the Rate Card/tier simply
  /// not resolving to a suggestion, just leaves the Salary field as it
  /// already was.
  Future<void> _loadRateCards() async {
    try {
      final rateCards = await ref.read(rateCardRepositoryProvider).get();
      if (!mounted) return;
      setState(() => _rateCards = rateCards.map((w) => w.rateCard).toList());
      _refreshSuggestedSalary();
    } catch (_) {
      // Fail open — see doc comment above.
    }
  }

  /// Recomputes the suggested Salary from the current Duration Care is
  /// Needed + care-tier selections and, if it changed, refills the field —
  /// but only when the field is still empty or still holds our own
  /// previous suggestion, never overwriting something admin typed
  /// themselves (or a pre-filled existing job's real salary_amount). Used
  /// both by [_loadRateCards] on the initial fetch and after any later
  /// change to _careDuration/_toiletAssistance/_feedingType/_medicalConditions.
  void _refreshSuggestedSalary() {
    if (_careDuration == null) return;
    final tier = deriveCareTier(_careReceiverForTierDerivation);
    final frequency = frequencyForCareDuration(_careDuration!);
    final suggestion = suggestedRate(_rateCards, tier, frequency);
    if (suggestion == null) return;
    if (_salaryController.text.isEmpty || _salaryController.text == _lastAutoSuggestedSalary) {
      _salaryController.text = suggestion;
      _lastAutoSuggestedSalary = suggestion;
    }
  }

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    final cr = widget.careReceiver;
    if (job != null && cr != null) {
      _city = job.city;
      _areaController.text = job.area ?? '';
      _dutyType = job.dutyType;
      _careDuration = job.careDuration;
      _startDate =
          job.startDate == null ? null : DateTime.tryParse(job.startDate!);
      _languages =
          job.languages.isEmpty ? [_noPreferenceLanguage] : List.of(job.languages);
      _salaryController.text = job.salaryAmount ?? '';
      _preferredGender = job.preferredGender;
      _preferredReligion = job.preferredReligion;

      _patientNameController.text = cr.patientName ?? '';
      _ageController.text = cr.age.toString();
      _gender = cr.gender;
      _weightController.text = cr.weightKg.toString();
      _feedingType = cr.feedingType;
      // Empty/false source means the job was itself "None" —
      // _medicalConditions already defaults to that, so leave it untouched.
      if (cr.hasMedicalCondition && cr.medicalConditions.isNotEmpty) {
        _medicalConditions = List.of(cr.medicalConditions);
      }
      _medicalConditionOtherController.text = cr.medicalConditionOther ?? '';
      _toiletAssistance = List.of(cr.toiletAssistance);
      _toiletAssistanceOtherController.text = cr.toiletAssistanceOther ?? '';
    }
    _loadRateCards();
  }

  @override
  void dispose() {
    _patientNameController.dispose();
    _areaController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _salaryController.dispose();
    _patientNameFocusNode.dispose();
    _areaFocusNode.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _salaryFocusNode.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());

  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isPatientNameValid => Validators.isValidName(_patientNameController.text.trim());
  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid =>
      _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isStartDateValid => _startDate != null;
  bool get _isCareDurationValid => _careDuration != null;
  bool get _isToiletAssistanceValid => _toiletAssistance.isNotEmpty;
  bool get _isFeedingTypeValid => _feedingType != null;
  bool get _isSalaryValid => _salaryController.text.trim().isNotEmpty;

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
      _isPatientNameValid &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isDutyTypeValid &&
      _isStartDateValid &&
      _isCareDurationValid &&
      _isToiletAssistanceValid &&
      _isFeedingTypeValid &&
      _isSalaryValid;

  /// In on-form order, so the first invalid one found here is genuinely
  /// the first one the admin sees when Post scrolls them to it. Medical
  /// Condition isn't here — it always defaults to "None" and can never be
  /// empty, so it's never invalid (mirrors nursenow-app's own forms).
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_patientNameKey, _isPatientNameValid, focusNode: _patientNameFocusNode),
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid,
            focusNode: _weightFocusNode),
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_startDateKey, _isStartDateValid),
        _MandatoryField(_careDurationKey, _isCareDurationValid),
        _MandatoryField(_toiletAssistanceKey, _isToiletAssistanceValid),
        _MandatoryField(_feedingTypeKey, _isFeedingTypeValid),
        _MandatoryField(_salaryKey, _isSalaryValid,
            focusNode: _salaryFocusNode),
      ];


  /// "None" is mutually exclusive with every real condition: picking it
  /// clears any real selections, and picking a real condition clears
  /// "None". Deselecting the last real condition (or re-tapping "None"
  /// while it's the only thing selected) falls back to "None" — there's no
  /// truly-empty state, which is what makes this field mandatory without
  /// needing a separate red-highlight check. Mirrors nursenow-app's
  /// Post/Edit Requirement screens exactly. Must be called inside setState.
  void _applyMedicalConditionSelection(List<String> next) {
    final added = next.where((c) => !_medicalConditions.contains(c));
    final removed = _medicalConditions.where((c) => !next.contains(c));
    if (added.contains(_noneMedicalCondition)) {
      _medicalConditions = [_noneMedicalCondition];
    } else if (added.isNotEmpty) {
      _medicalConditions = next.where((c) => c != _noneMedicalCondition).toList();
    } else if (removed.isNotEmpty) {
      final remaining = next.where((c) => c != _noneMedicalCondition).toList();
      _medicalConditions = remaining.isEmpty ? [_noneMedicalCondition] : remaining;
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
      final hasMedicalCondition = !_medicalConditions.contains(_noneMedicalCondition);
      final careReceiver = CareReceiverInput(
        patientName: _patientNameController.text.trim(),
        age: _age!,
        gender: _gender!,
        weightKg: _weightKg!,
        feedingType: _feedingType,
        hasMedicalCondition: hasMedicalCondition,
        medicalConditions: hasMedicalCondition ? _medicalConditions : null,
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
        requiresVitalMonitoring: false,
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
              dutyType: _dutyType!,
              frequencyOfCare: _derivedFrequencyOfCare!,
              startDate: startDate,
              languages: _effectiveLanguages,
              salaryAmount: _salaryController.text.trim(),
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
              careDuration: _careDuration!,
            );
      } else {
        await ref.read(adminJobsRepositoryProvider).create(
              careReceiver: careReceiver,
              city: _city!,
              area: _areaController.text.trim(),
              dutyType: _dutyType!,
              frequencyOfCare: _derivedFrequencyOfCare!,
              startDate: startDate,
              languages: _effectiveLanguages,
              salaryAmount: _salaryController.text.trim(),
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
              careDuration: _careDuration!,
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------
  // Individual field builders — extracted so the two field orderings below
  // (admin's own job posting vs. editing a NurseNow individual's
  // requirement) can freely reuse/reorder the same widgets without
  // duplicating their logic. Each returns its own leading spacer so callers
  // can just spread them one after another.
  // ---------------------------------------------------------------------

  List<Widget> _cityField() => [
        KeyedSubtree(
          key: _cityKey,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _city,
            decoration: InputDecoration(
              labelText: 'City (Mandatory)',
              errorText: _showValidationErrors && !_isCityValid ? 'Please select a city' : null,
            ),
            items: City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))).toList(),
            onChanged: (value) => setState(() => _city = value),
          ),
        ),
      ];

  List<Widget> _areaField() => _city == null
      ? []
      : [
          const SizedBox(height: AppSpacing.sm),
          KeyedSubtree(
            key: _areaKey,
            child: TextField(
              controller: _areaController,
              focusNode: _areaFocusNode,
              decoration: InputDecoration(
                labelText: 'Area in ${City.displayNames[_city] ?? _city} (Mandatory)',
                errorText: _showValidationErrors && !_isAreaValid ? 'Area is required' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ];

  List<Widget> _patientNameField() => [
        KeyedSubtree(
          key: _patientNameKey,
          child: TextField(
            controller: _patientNameController,
            focusNode: _patientNameFocusNode,
            maxLength: Validation.nameMaxLength,
            decoration: InputDecoration(
              labelText: "Patient's Name (Mandatory)",
              errorText: _showValidationErrors && !_isPatientNameValid
                  ? 'Enter the patient\'s name (letters only, max ${Validation.nameMaxLength} characters)'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ];

  List<Widget> _ageField() => [
        KeyedSubtree(
          key: _ageKey,
          child: TextField(
            controller: _ageController,
            focusNode: _ageFocusNode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Patient's Age (Mandatory)",
              errorText: _showValidationErrors && !_isAgeValid ? 'Age is required (1-120)' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ];

  List<Widget> _genderField() => [
        KeyedSubtree(
          key: _genderKey,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _gender,
            decoration: InputDecoration(
              labelText: "Patient's Gender (Mandatory)",
              errorText: _showValidationErrors && !_isGenderValid ? 'Please select a gender' : null,
            ),
            items: const [
              DropdownMenuItem(value: Gender.male, child: Text('Male')),
              DropdownMenuItem(value: Gender.female, child: Text('Female')),
              DropdownMenuItem(value: Gender.other, child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _gender = value),
          ),
        ),
      ];

  List<Widget> _weightField() => [
        KeyedSubtree(
          key: _weightKey,
          child: TextField(
            controller: _weightController,
            focusNode: _weightFocusNode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Patient's Weight (kg) (Mandatory)",
              errorText: _showValidationErrors && !_isWeightValid ? 'Weight is required (1-300 kg)' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ];

  // Relabeled to match nursenow-app's own forms exactly, now that this
  // dialog's field set/order is fully unified with them. Mandatory, like
  // Toilet Assistance below.
  List<Widget> _feedingField() => [
        DropdownButtonFormField<String>(
          key: _feedingTypeKey,
          isExpanded: true,
          initialValue: _feedingType,
          decoration: InputDecoration(
            labelText: 'Feeding/Medicine Assistance (Mandatory)',
            errorText: _showValidationErrors && !_isFeedingTypeValid
                ? 'Please select feeding/medicine assistance'
                : null,
          ),
          items: FeedingType.all
              .map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f)))
              .toList(),
          onChanged: (value) => setState(() {
            _feedingType = value;
            _refreshSuggestedSalary();
          }),
        ),
      ];

  // Always-visible, mandatory multi-select with a "None" sentinel — mirrors
  // nursenow-app's Post/Edit Requirement screens exactly, replacing the old
  // toggle-then-reveal pattern. Never truly empty (see
  // _applyMedicalConditionSelection), so it needs no separate red-highlight
  // validation.
  List<Widget> _medicalConditionSection() => [
        const Text('Medical Condition (Mandatory)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.xs),
        VitaMultiSelectChips(
          options: [_noneMedicalCondition, ...MedicalCondition.all],
          labels: {_noneMedicalCondition: _noneMedicalConditionLabel, ...MedicalCondition.displayNames},
          selected: _medicalConditions,
          onChanged: (next) => setState(() {
            _applyMedicalConditionSelection(next);
            _refreshSuggestedSalary();
          }),
        ),
        if (_medicalConditions.contains(MedicalCondition.other)) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _medicalConditionOtherController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Please describe the other condition'),
          ),
        ],
      ];

  // A single-select dropdown, not a multi-select — behavior of "Others"
  // revealing the free-text field is unchanged.
  List<Widget> _toiletAssistanceSection() => [
        DropdownButtonFormField<String>(
          key: _toiletAssistanceKey,
          isExpanded: true,
          initialValue: _toiletAssistance.isEmpty ? null : _toiletAssistance.first,
          decoration: InputDecoration(
            labelText: 'Toilet Assistance (Mandatory)',
            errorText: _showValidationErrors && !_isToiletAssistanceValid
                ? 'Please select toilet assistance'
                : null,
          ),
          items: ToiletAssistance.all
              .map((t) => DropdownMenuItem(value: t, child: Text(ToiletAssistance.displayNames[t] ?? t)))
              .toList(),
          onChanged: (value) => setState(() {
            _toiletAssistance = [value!];
            _refreshSuggestedSalary();
          }),
        ),
        if (_toiletAssistance.contains(ToiletAssistance.others)) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _toiletAssistanceOtherController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Please describe the other toilet assistance'),
          ),
        ],
      ];

  List<Widget> _dutyTypeField() => [
        KeyedSubtree(
          key: _dutyTypeKey,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _dutyType,
            decoration: InputDecoration(
              labelText: 'Hours Care Needed (Mandatory)',
              errorText: _showValidationErrors && !_isDutyTypeValid ? 'Please select duty hours' : null,
            ),
            items: DutyType.all.map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d))).toList(),
            onChanged: (value) => setState(() => _dutyType = value),
          ),
        ),
      ];

  // Always derived from Duration Care is Needed (see
  // _derivedFrequencyOfCare) — never a manual pick, for either admin's own
  // posting or a NurseNow individual's requirement. Lives in the Nurse Fee
  // Guidance section, same as nursenow-app's own forms.
  List<Widget> _frequencyField() => [
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Frequency of Care'),
          child: Text(FrequencyOfCare.displayNames[_derivedFrequencyOfCare] ?? '-'),
        ),
      ];

  // Pre-filled with the Rate Card's suggested figure for the derived care
  // tier + frequency once it loads (see _loadRateCards), refreshed as
  // related fields change (see _refreshSuggestedSalary) — but never
  // overwriting something admin already typed. Free text, not a number, so
  // it can carry a range or a note exactly as admin wrote it in the Rate
  // Card — same field type nursenow-app's own forms use.
  List<Widget> _salaryField() => [
        KeyedSubtree(
          key: _salaryKey,
          child: TextField(
            controller: _salaryController,
            focusNode: _salaryFocusNode,
            maxLines: null,
            decoration: InputDecoration(
              labelText: 'Salary (₹/${_salaryUnit(_derivedFrequencyOfCare)}) (Mandatory)',
              errorText: _showValidationErrors && !_isSalaryValid ? 'Salary is required' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ];

  List<Widget> _careDurationField() => [
        KeyedSubtree(
          key: _careDurationKey,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _careDuration,
            decoration: InputDecoration(
              labelText: 'Duration Care is Needed (Mandatory)',
              errorText:
                  _showValidationErrors && !_isCareDurationValid ? 'Please select how long care is needed' : null,
            ),
            items: CareDuration.all
                .map((d) => DropdownMenuItem(value: d, child: Text(CareDuration.displayNames[d] ?? d)))
                .toList(),
            onChanged: (value) => setState(() {
              _careDuration = value;
              _refreshSuggestedSalary();
            }),
          ),
        ),
      ];

  List<Widget> _startDateField() => [
        KeyedSubtree(
          key: _startDateKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A persistent heading, unlike the old design where the
              // button's own label doubled as the display text — that
              // meant "Preferred Start Date" disappeared the moment a date
              // was picked, leaving just a bare date with no context for
              // what it was.
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: _showValidationErrors && !_isStartDateValid ? AppColors.error : AppColors.primaryDark,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'Preferred Start Date (Mandatory)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _showValidationErrors && !_isStartDateValid ? AppColors.error : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: _pickStartDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _startDate == null
                      ? 'Select date'
                      : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
              if (_showValidationErrors && !_isStartDateValid)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Please select a start date', style: TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
                ),
            ],
          ),
        ),
      ];

  List<Widget> _preferredGenderField() => [
        DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: _preferredGender,
          decoration: const InputDecoration(labelText: 'Preferred Caregiver Gender'),
          items: const [
            DropdownMenuItem<String?>(value: null, child: Text('No preference')),
            DropdownMenuItem<String?>(value: Gender.male, child: Text('Male')),
            DropdownMenuItem<String?>(value: Gender.female, child: Text('Female')),
          ],
          onChanged: (value) => setState(() => _preferredGender = value),
        ),
      ];


  static const _sectionHeading = TextStyle(fontWeight: FontWeight.bold);
  static const _spacerSm = SizedBox(height: AppSpacing.sm);
  static const _spacerLg = SizedBox(height: AppSpacing.lg);

  /// One unified field set and order for every job admin creates or
  /// edits — whether it's admin's own from-scratch posting or approving/
  /// editing a NurseNow individual's own requirement — matching
  /// nursenow-app's own Post/Edit Requirement screens exactly (see
  /// post_requirement_screen.dart/edit_requirement_screen.dart): Patient
  /// Details / Care Preferences / Nurse Fee Guidance. Admin never sees or
  /// sets anything the patient/family isn't also asked for.
  List<Widget> _fields() => [
        const Text('Patient Details', style: _sectionHeading),
        _spacerSm,
        ..._patientNameField(),
        _spacerSm,
        ..._ageField(),
        _spacerSm,
        ..._genderField(),
        _spacerSm,
        ..._weightField(),
        _spacerSm,
        ..._cityField(),
        ..._areaField(),
        _spacerLg,
        ..._medicalConditionSection(),
        _spacerLg,
        const Text('Care Preferences', style: _sectionHeading),
        _spacerSm,
        ..._dutyTypeField(),
        _spacerSm,
        ..._startDateField(),
        _spacerSm,
        ..._careDurationField(),
        _spacerSm,
        ..._toiletAssistanceSection(),
        _spacerSm,
        ..._feedingField(),
        _spacerSm,
        ..._preferredGenderField(),
        _spacerLg,
        const Text('Nurse Fee Guidance', style: _sectionHeading),
        _spacerSm,
        ..._frequencyField(),
        _spacerSm,
        ..._salaryField(),
      ];

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
              ..._fields(),
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
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          // Always clickable — missing fields are handled inside
          // _handlePostPressed (highlight + scroll), not by disabling this.
          onPressed: _submitting ? null : _handlePostPressed,
          icon: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(_isEditing ? 'Save Changes' : 'Post'),
        ),
      ],
    );
  }
}

/// Guards the permanent bulk delete — this destroys rows and, via cascade,
/// every candidate application against them, with no undo. Confirm stays
/// disabled until the admin types the literal word DELETE, the highest-
/// friction confirmation pattern already used in this codebase (see e.g.
/// admin-web's other irreversible actions) — a stray click can't trigger it.
class _BulkDeleteConfirmDialog extends StatefulWidget {
  final int count;
  final List<String> sampleDisplayIds;

  const _BulkDeleteConfirmDialog({required this.count, required this.sampleDisplayIds});

  @override
  State<_BulkDeleteConfirmDialog> createState() => _BulkDeleteConfirmDialogState();
}

class _BulkDeleteConfirmDialogState extends State<_BulkDeleteConfirmDialog> {
  final _confirmController = TextEditingController();
  bool _canConfirm = false;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() {
      final matches = _confirmController.text.trim() == 'DELETE';
      if (matches != _canConfirm) setState(() => _canConfirm = matches);
    });
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.count - widget.sampleDisplayIds.length;
    return AlertDialog(
      title: Text('Permanently delete ${widget.count} posting(s)?'),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This cannot be undone. Every candidate application against these '
              'postings will also be permanently deleted from the database, as if '
              'they had never applied.',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.sampleDisplayIds.join(', ') + (remaining > 0 ? ', and $remaining more' : ''),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Type DELETE to confirm:', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _confirmController,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              onSubmitted: (_) {
                if (_canConfirm) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _canConfirm ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          child: const Text('Delete Permanently'),
        ),
      ],
    );
  }
}
