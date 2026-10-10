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
import '../widgets/job_progress_stepper.dart';
import '../widgets/job_status_chip.dart';

/// "My Jobs" — every job/requirement this caregiver has ever gone for,
/// split into 3 sub-tabs matching the stage of that application: Applied
/// (waiting on a decision), Selected (currently accepted), and Past
/// (completed, withdrawn, or not selected). Exactly the same three
/// MyApplicationModel states CLAUDE.md documents (applied/accepted/
/// completed/rejected, decided_by_admin, applied_at) — only the layout is
/// new, split across tabs instead of one long mixed list; see
/// job_status_chip.dart/job_progress_stepper.dart for the one place that
/// derivation happens.
///
/// Data sources, one per tab:
///  - Applied: the same active-listing endpoints jobs_screen.dart (Find
///    Jobs) uses, filtered to myApplication.status == applied. A pending
///    application is still just a row on an ACTIVE job/requirement, so
///    there's no separate "my applications" endpoint for it.
///  - Selected: GET /caregiver/jobs/assigned + .../organisation-requirements/
///    assigned, filtered to status == accepted (completed rows are shown
///    on the Past tab instead, not duplicated here).
///  - Past: the new GET /caregiver/jobs/history + .../organisation-
///    requirements/history (added for this redesign so a closed job
///    doesn't silently disappear from every list once it's no longer
///    active), filtered to completed, or to rejected WITH an appliedAt
///    (i.e. a real past application, not a plain pre-apply "not
///    interested" decline — those stay only in Find Jobs' own collapsed
///    section, so they're not shown twice).
class MyAssignmentScreen extends ConsumerStatefulWidget {
  const MyAssignmentScreen({super.key});

  @override
  ConsumerState<MyAssignmentScreen> createState() => _MyAssignmentScreenState();
}

class _MyAssignmentScreenState extends ConsumerState<MyAssignmentScreen> {
  List<JobModel> _activeJobs = [];
  List<OrganisationRequirementModel> _activeRequirements = [];
  List<JobModel> _assignedJobs = [];
  List<OrganisationRequirementModel> _assignedRequirements = [];
  List<JobModel> _jobHistory = [];
  List<OrganisationRequirementModel> _requirementHistory = [];

  bool _loading = true;
  String? _errorMessage;
  final Set<String> _busyId = {};
  // Mirrors the reference design's Past-tab filter chips exactly.
  String _pastFilter = _kPastAll;

  static const _kPastAll = 'all';
  static const _kPastCompleted = 'completed';
  static const _kPastNotSelected = 'not_selected';
  static const _kPastWithdrawn = 'withdrawn';

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
      final activeJobs = await ref.read(jobsRepositoryProvider).listActiveJobs();
      final activeRequirements = await ref.read(organisationOpeningsRepositoryProvider).listActive();
      final assignedJobs = await ref.read(jobsRepositoryProvider).getAssignedJobs();
      final assignedRequirements = await ref.read(organisationOpeningsRepositoryProvider).getAssigned();
      final jobHistory = await ref.read(jobsRepositoryProvider).getJobHistory();
      final requirementHistory = await ref.read(organisationOpeningsRepositoryProvider).getHistory();
      if (mounted) {
        setState(() {
          _activeJobs = activeJobs;
          _activeRequirements = activeRequirements;
          _assignedJobs = assignedJobs;
          _assignedRequirements = assignedRequirements;
          _jobHistory = jobHistory;
          _requirementHistory = requirementHistory;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Withdrawing a still-pending application — same backend call as
  /// declining a job before ever applying (POST .../apply with
  /// status=rejected), the only difference being this one already has an
  /// appliedAt, which is exactly the signal job_status_chip.dart uses to
  /// label it "Withdrawn by you" rather than "Not interested".
  Future<void> _withdrawJob(JobModel job) async {
    if (!await _confirmWithdraw(jobDisplayId(job))) return;
    setState(() => _busyId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).applyToJob(job.id, JobApplicationStatus.rejected);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showVitaErrorBanner(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId.remove(job.id));
    }
  }

  Future<void> _withdrawRequirement(OrganisationRequirementModel requirement) async {
    if (!await _confirmWithdraw(organisationJobDisplayId(requirement))) return;
    setState(() => _busyId.add(requirement.id));
    try {
      await ref.read(organisationOpeningsRepositoryProvider).apply(requirement.id, JobApplicationStatus.rejected);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showVitaErrorBanner(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId.remove(requirement.id));
    }
  }

  Future<bool> _confirmWithdraw(String displayId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: Text('You are withdrawing your application to $displayId. You can apply again later if it\'s still open.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Withdraw')),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Closing an accepted job is the only exit from `assigned` for it — same
  /// server call as the old "Mark Complete" (job_applications.status ->
  /// completed). Labeled "Close", not "Reject" — the resulting status is
  /// 'completed' (work done).
  Future<void> _completeJob(JobModel job) async {
    final reason = await _showCloseReasonDialog(
      title: 'Close this job?',
      message:
          "This marks ${jobDisplayId(job)} as closed — work completed. You can apply again later if it's still "
          "open. If you don't have any other accepted jobs, you'll be shown as available for new ones again.",
      confirmLabel: 'Close Duty',
    );
    if (reason == null || !mounted) return;

    setState(() => _busyId.add(job.id));
    try {
      final stillAssigned = await ref.read(jobsRepositoryProvider).completeJob(job.id, closeReason: reason);
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
      if (mounted) showVitaErrorBanner(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId.remove(job.id));
    }
  }

  /// Same as [_completeJob], for an organisation requirement.
  Future<void> _completeRequirement(OrganisationRequirementModel requirement) async {
    final reason = await _showCloseReasonDialog(
      title: 'Close this requirement?',
      message:
          "This marks ${organisationJobDisplayId(requirement)} as closed — work completed. You can apply again "
          "later if it's still open. If you don't have any other accepted jobs or requirements, you'll be shown "
          "as available for new ones again.",
      confirmLabel: 'Close Duty',
    );
    if (reason == null || !mounted) return;

    setState(() => _busyId.add(requirement.id));
    try {
      final verificationStatus =
          await ref.read(organisationOpeningsRepositoryProvider).complete(requirement.id, closeReason: reason);
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
      if (mounted) showVitaErrorBanner(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId.remove(requirement.id));
    }
  }

  /// Shared confirmation dialog for closing an accepted job/requirement —
  /// a fixed dropdown of reasons, defaulting to CaregiverCloseReason.
  /// noReason so a caregiver who confirms without picking anything else
  /// still always submits a real, explicit value.
  Future<String?> _showCloseReasonDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    String selectedReason = CaregiverCloseReason.noReason;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: AppSpacing.md),
              const Text('Reason for closing', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedReason,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: CaregiverCloseReason.all
                    .map((r) => DropdownMenuItem(value: r, child: Text(CaregiverCloseReason.displayNames[r] ?? r)))
                    .toList(),
                onChanged: (value) => setDialogState(() => selectedReason = value ?? selectedReason),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(selectedReason), child: Text(confirmLabel)),
          ],
        ),
      ),
    );
  }

  List<JobModel> get _appliedJobs =>
      _activeJobs.where((j) => j.myApplication?.status == JobApplicationStatus.applied).toList();
  List<OrganisationRequirementModel> get _appliedRequirements =>
      _activeRequirements.where((r) => r.myApplication?.status == JobApplicationStatus.applied).toList();

  List<JobModel> get _selectedJobs =>
      _assignedJobs.where((j) => j.myApplication?.status == JobApplicationStatus.accepted).toList();
  List<OrganisationRequirementModel> get _selectedRequirements =>
      _assignedRequirements.where((r) => r.myApplication?.status == JobApplicationStatus.accepted).toList();

  bool _isPastRow(String status, bool hasAppliedAt) =>
      status == JobApplicationStatus.completed || (status == JobApplicationStatus.rejected && hasAppliedAt);

  bool _matchesPastFilter(String status, bool decidedByAdmin) {
    switch (_pastFilter) {
      case _kPastCompleted:
        return status == JobApplicationStatus.completed;
      case _kPastNotSelected:
        return status == JobApplicationStatus.rejected && decidedByAdmin;
      case _kPastWithdrawn:
        return status == JobApplicationStatus.rejected && !decidedByAdmin;
      default:
        return true;
    }
  }

  List<JobModel> get _pastJobs => _jobHistory.where((j) {
        final app = j.myApplication;
        if (app == null) return false;
        if (!_isPastRow(app.status, app.appliedAt != null)) return false;
        return _matchesPastFilter(app.status, app.decidedByAdmin);
      }).toList();

  List<OrganisationRequirementModel> get _pastRequirements => _requirementHistory.where((r) {
        final app = r.myApplication;
        if (app == null) return false;
        if (!_isPastRow(app.status, app.appliedAt != null)) return false;
        return _matchesPastFilter(app.status, app.decidedByAdmin);
      }).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const VitaAppBarTitle('My Jobs'),
          actions: caregiverAppBarActions(showBell: true),
          bottom: const TabBar(
            tabs: [Tab(text: 'Applied'), Tab(text: 'Selected'), Tab(text: 'Past')],
          ),
        ),
        backgroundColor: AppColors.background,
        bottomNavigationBar: const CaregiverBottomNav(currentIndex: 2),
        body: SafeArea(
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : TabBarView(
                  children: [
                    _buildAppliedTab(),
                    _buildSelectedTab(),
                    _buildPastTab(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAppliedTab() {
    final jobs = _appliedJobs;
    final requirements = _appliedRequirements;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_errorMessage != null) Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          if (jobs.isEmpty && requirements.isEmpty && _errorMessage == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                "You haven't applied to anything yet. Find jobs on the Find Jobs tab.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final job in jobs) ...[
            _ApplicationCard(
              title: JobDetailCard(job: job),
              stepperStage: jobStepperStage(applicationStatus: JobApplicationStatus.applied, startDate: job.startDate),
              status: jobCardStatus(status: JobApplicationStatus.applied, decidedByAdmin: false, hasAppliedAt: true),
              timeline: job.myApplication != null ? ApplicationTimeline(job.myApplication!) : null,
              actionLabel: 'Withdraw Application',
              busy: _busyId.contains(job.id),
              onAction: () => _withdrawJob(job),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final requirement in requirements) ...[
            _ApplicationCard(
              title: _RequirementSummary(requirement: requirement),
              stepperStage: jobStepperStage(applicationStatus: JobApplicationStatus.applied, startDate: null),
              status: jobCardStatus(status: JobApplicationStatus.applied, decidedByAdmin: false, hasAppliedAt: true),
              timeline: requirement.myApplication != null ? ApplicationTimeline(requirement.myApplication!) : null,
              actionLabel: 'Withdraw Application',
              busy: _busyId.contains(requirement.id),
              onAction: () => _withdrawRequirement(requirement),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedTab() {
    final jobs = _selectedJobs;
    final requirements = _selectedRequirements;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_errorMessage != null) Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          if (jobs.isEmpty && requirements.isEmpty && _errorMessage == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                "You haven't been selected for anything yet.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final job in jobs) ...[
            _ApplicationCard(
              title: JobDetailCard(job: job),
              stepperStage: jobStepperStage(applicationStatus: JobApplicationStatus.accepted, startDate: job.startDate),
              status: jobCardStatus(
                status: JobApplicationStatus.accepted,
                decidedByAdmin: job.myApplication?.decidedByAdmin ?? true,
                hasAppliedAt: true,
                onDuty: (jobStepperStage(applicationStatus: JobApplicationStatus.accepted, startDate: job.startDate) ?? 1) >= 2,
              ),
              timeline: job.myApplication != null ? ApplicationTimeline(job.myApplication!) : null,
              contactCard: job.jobPoster != null ? JobPosterContactCard(poster: job.jobPoster!) : null,
              actionLabel: 'Close Duty',
              busy: _busyId.contains(job.id),
              onAction: () => _completeJob(job),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final requirement in requirements) ...[
            _ApplicationCard(
              title: _RequirementSummary(requirement: requirement),
              stepperStage: jobStepperStage(applicationStatus: JobApplicationStatus.accepted, startDate: null),
              status: jobCardStatus(
                status: JobApplicationStatus.accepted,
                decidedByAdmin: requirement.myApplication?.decidedByAdmin ?? true,
                hasAppliedAt: true,
              ),
              timeline: requirement.myApplication != null ? ApplicationTimeline(requirement.myApplication!) : null,
              contactCard: requirement.organisationPhone != null
                  ? JobPosterContactCard(
                      poster: JobPosterModel(
                        fullName: requirement.organisationName ?? 'Organisation',
                        phone: requirement.organisationPhone!,
                      ),
                    )
                  : null,
              actionLabel: 'Close Duty',
              busy: _busyId.contains(requirement.id),
              onAction: () => _completeRequirement(requirement),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  Widget _buildPastTab() {
    final jobs = _pastJobs;
    final requirements = _pastRequirements;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_errorMessage != null) Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              _PastFilterChip(label: 'All', value: _kPastAll, selected: _pastFilter, onSelected: _setPastFilter),
              _PastFilterChip(
                  label: 'Completed', value: _kPastCompleted, selected: _pastFilter, onSelected: _setPastFilter),
              _PastFilterChip(
                  label: 'Not selected', value: _kPastNotSelected, selected: _pastFilter, onSelected: _setPastFilter),
              _PastFilterChip(
                  label: 'Withdrawn', value: _kPastWithdrawn, selected: _pastFilter, onSelected: _setPastFilter),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (jobs.isEmpty && requirements.isEmpty && _errorMessage == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                'Nothing here yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final job in jobs) ...[
            _ApplicationCard(
              title: JobDetailCard(job: job),
              stepperStage: jobStepperStage(applicationStatus: job.myApplication!.status, startDate: job.startDate),
              status: jobCardStatus(
                status: job.myApplication!.status,
                decidedByAdmin: job.myApplication!.decidedByAdmin,
                hasAppliedAt: job.myApplication!.appliedAt != null,
              ),
              timeline: ApplicationTimeline(job.myApplication!),
              contactCard: job.jobPoster != null ? JobPosterContactCard(poster: job.jobPoster!, showPhone: false) : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final requirement in requirements) ...[
            _ApplicationCard(
              title: _RequirementSummary(requirement: requirement),
              stepperStage: jobStepperStage(applicationStatus: requirement.myApplication!.status, startDate: null),
              status: jobCardStatus(
                status: requirement.myApplication!.status,
                decidedByAdmin: requirement.myApplication!.decidedByAdmin,
                hasAppliedAt: requirement.myApplication!.appliedAt != null,
              ),
              timeline: ApplicationTimeline(requirement.myApplication!),
              contactCard: requirement.organisationPhone != null
                  ? JobPosterContactCard(
                      poster: JobPosterModel(
                        fullName: requirement.organisationName ?? 'Organisation',
                        phone: requirement.organisationPhone!,
                      ),
                      showPhone: false,
                    )
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  void _setPastFilter(String value) => setState(() => _pastFilter = value);
}

class _PastFilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final void Function(String) onSelected;

  const _PastFilterChip({required this.label, required this.value, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onSelected(value),
    );
  }
}

/// A single card shared by all 3 My Jobs tabs — the job/requirement's own
/// summary widget up top, then the stepper (when applicable), status
/// chip, timeline, an optional "Call coordinator" contact card, and an
/// optional single action button at the bottom. Every one of these pieces
/// is either reused as-is from elsewhere (JobDetailCard/
/// JobPosterContactCard/ApplicationTimeline) or newly built purely as a
/// display layer over existing data (JobProgressStepper/JobStatusChip) —
/// nothing here is a new backend concept.
class _ApplicationCard extends StatelessWidget {
  final Widget title;
  final int? stepperStage;
  final JobCardStatus status;
  final Widget? timeline;
  final Widget? contactCard;
  final String? actionLabel;
  final bool busy;
  final VoidCallback? onAction;

  const _ApplicationCard({
    required this.title,
    required this.stepperStage,
    required this.status,
    this.timeline,
    this.contactCard,
    this.actionLabel,
    this.busy = false,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: status.color, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.sm),
          if (stepperStage != null) ...[
            JobProgressStepper(currentStage: stepperStage!),
            const SizedBox(height: AppSpacing.sm),
          ],
          JobStatusChip(status: status),
          if (status.explanation != null) ...[
            const SizedBox(height: 2),
            Text(status.explanation!, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
          ],
          if (timeline != null) ...[
            const SizedBox(height: AppSpacing.sm),
            timeline!,
          ],
          if (contactCard != null) ...[
            const SizedBox(height: AppSpacing.md),
            contactCard!,
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _ActionButton(label: actionLabel!, busy: busy, onPressed: onAction),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _ActionButton({required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isWithdraw = label == 'Withdraw Application';
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: isWithdraw ? AppColors.error : AppColors.success,
        side: BorderSide(color: isWithdraw ? AppColors.error : AppColors.success),
      ),
      icon: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isWithdraw ? AppColors.error : AppColors.success,
              ),
            )
          : Icon(isWithdraw ? Icons.undo : Icons.task_alt, size: 18),
      label: Text(label),
    );
  }
}

/// A compact, read-only summary of an organisation requirement — the same
/// identity/location/tags block jobs_screen.dart's own requirement card
/// shows, minus the Apply button (every My Jobs tab supplies its own
/// single action at the card's own level instead).
class _RequirementSummary extends StatelessWidget {
  final OrganisationRequirementModel requirement;

  const _RequirementSummary({required this.requirement});

  String get _typeOfNurseText => requirement.typeOfNurse == TypeOfNurse.others && requirement.typeOfNurseOther != null
      ? requirement.typeOfNurseOther!
      : TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          organisationJobDisplayId(requirement),
          style: const TextStyle(fontSize: AppTypography.small, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 2),
        Text(
          requirement.organisationName ?? '',
          style: const TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold),
        ),
        Text(_typeOfNurseText, style: const TextStyle(color: AppColors.textSecondary)),
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
      ],
    );
  }
}
