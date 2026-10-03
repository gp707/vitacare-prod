import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/messages_bell.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../app/scope_of_work_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../caregiver_profile/screens/caregiver_profile_view_screen.dart';
import '../widgets/duty_requirements_button.dart';
import 'edit_requirement_screen.dart';

/// Full requirement history for this account — every past posting stays
/// visible (pending review / live / rejected / closed), not just the
/// current one, so a patient/family can always see who was accepted on a
/// past requirement even after it's closed. There is no "post a new
/// requirement" action anywhere in this screen any more — posting only
/// ever happens once, as part of registration itself (RegistrationScreen),
/// so every individual account has exactly one requirement in its history.
class JobsPostedScreen extends ConsumerStatefulWidget {
  const JobsPostedScreen({super.key});

  @override
  ConsumerState<JobsPostedScreen> createState() => _JobsPostedScreenState();
}

class _JobsPostedScreenState extends ConsumerState<JobsPostedScreen> {
  bool _loading = true;
  String? _error;
  List<JobModel> _requirements = [];
  Map<String, List<JobApplicationModel>> _applicationsByJobId = {};
  final Set<String> _decidingApplicationId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(individualRepositoryProvider);
      final requirements = await repo.listMyRequirements();
      // pending_review can never have applications yet — skip the request
      // for those, fetch for every other requirement (active AND closed,
      // so a past requirement's accepted/declined applicants stay visible
      // after it closes, not just while it's live).
      final withApplications = requirements
          .where((r) => r.status != JobStatus.pendingReview)
          .toList();
      final applicationLists = await Future.wait(
          withApplications.map((r) => repo.listApplications(r.id)));
      if (!mounted) return;
      setState(() {
        _requirements = requirements;
        _applicationsByJobId = {
          for (var i = 0; i < withApplications.length; i++)
            withApplications[i].id: applicationLists[i],
        };
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String jobId, String applicationId) async {
    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(individualRepositoryProvider).decideApplication(
          jobId, applicationId, JobApplicationStatus.accepted);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  /// A reason is mandatory (JOB_012 is the server-side backstop) — the
  /// dialog's Confirm button stays disabled until something is typed, so
  /// there's no way to submit a reject without one.
  Future<void> _rejectWithReason(String jobId, String applicationId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Decline this candidate'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 1000,
            maxLines: 3,
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(
                labelText: 'Reason (required, shown to no one but you)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () =>
                      Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(individualRepositoryProvider).decideApplication(
          jobId, applicationId, JobApplicationStatus.rejected,
          reason: reason);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  /// The single candidate currently under review, per the forced
  /// one-at-a-time flow — see _ApplicantsSection.
  void _viewProfile(String jobId, String applicationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaregiverProfileViewScreen(
          fetchProfile: () => ref
              .read(individualRepositoryProvider)
              .getApplicantProfile(jobId, applicationId),
        ),
      ),
    );
  }

  /// Allowed regardless of the requirement's own status (pending_review/
  /// active/closed) — only gated on there being no active application
  /// (see _RequirementCard._hasActiveApplication), matching the backend's
  /// own JOB_014 check.
  Future<void> _editRequirement(JobModel requirement) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => EditRequirementScreen(requirement: requirement)),
    );
    if (edited == true) await _load();
  }

  /// Allowed at any point in the requirement's lifecycle — regardless of
  /// applications, and regardless of whether it's already closed by an
  /// acceptance (see the backend's JOB_015, which only blocks cancelling
  /// something already rejected/cancelled). Confirmed first since it's
  /// irreversible and, when candidates are involved, notifies them by
  /// rejecting their application.
  Future<void> _cancelRequirement(JobModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this requirement?'),
        content: const Text(
          'Any candidates who applied or were accepted will have their application declined as '
          "cancelled, and you won't be able to see who applied afterward. You can make this "
          'requirement active again later, but today\'s applicant list will not come back.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No, keep it')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, cancel it',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(individualRepositoryProvider)
          .cancelRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    }
  }

  /// Brings a cancelled requirement back to active — no confirmation
  /// dialog needed (unlike cancel, this isn't destructive), matching
  /// Organisation's own "Unhide and Make it Live" action.
  Future<void> _reactivateRequirement(JobModel requirement) async {
    try {
      await ref
          .read(individualRepositoryProvider)
          .reactivateRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showVitaErrorBanner(context, e.message);
      }
    }
  }

  /// An individual account only ever has one requirement in its whole
  /// history (see "Registration IS posting" in CLAUDE.md), so there is no
  /// reason to hide anything behind a toggle — every requirement found is
  /// always shown directly.
  Widget _buildCard(JobModel requirement) {
    return _RequirementCard(
      requirement: requirement,
      applications: _applicationsByJobId[requirement.id] ?? const [],
      decidingApplicationId: _decidingApplicationId,
      onAccept: (applicationId) => _accept(requirement.id, applicationId),
      onReject: (applicationId) =>
          _rejectWithReason(requirement.id, applicationId),
      onViewProfile: (applicationId) =>
          _viewProfile(requirement.id, applicationId),
      onEdit: () => _editRequirement(requirement),
      onCancel: () => _cancelRequirement(requirement),
      onReactivate: () => _reactivateRequirement(requirement),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('Requirement Posted'),
        actions: individualAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const NurseNowBottomNav(currentIndex: 1),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_error != null)
                      Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                    if (_requirements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          "You don't have any requirements posted yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      for (final requirement in _requirements) ...[
                        _buildCard(requirement),
                        const SizedBox(height: AppSpacing.md),
                      ],
                  ],
                ),
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// Seconds are included (not just hours:minutes) so two actions taken within
// the same minute — e.g. a caregiver rejecting right after another applied —
// still display in a visibly distinguishable, correctly ordered sequence.
// The underlying DateTime already carries full precision from the backend
// (Postgres timestamptz); this only affects what's shown, not how anything
// is sorted (sorting already compares full DateTime/ISO values).
String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:'
    '${date.second.toString().padLeft(2, '0')}';

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: AppTypography.small,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary),
    );
  }
}

/// A single label/value line in the expanded details — label on its own
/// line in a small secondary color, value below it in the default body
/// style, so every field is unambiguous at a glance instead of relying on
/// a reader to infer meaning from a bare chip's text alone.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTypography.small, color: AppColors.textSecondary)),
          Text(value),
        ],
      ),
    );
  }
}

class _RequirementCard extends ConsumerStatefulWidget {
  final JobModel requirement;
  final List<JobApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId) onAccept;
  final void Function(String applicationId) onReject;
  final void Function(String applicationId) onViewProfile;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onReactivate;

  const _RequirementCard({
    required this.requirement,
    required this.applications,
    required this.decidingApplicationId,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
    required this.onEdit,
    required this.onCancel,
    required this.onReactivate,
  });

  @override
  ConsumerState<_RequirementCard> createState() => _RequirementCardState();
}

class _RequirementCardState extends ConsumerState<_RequirementCard> {
  bool _detailsExpanded = false;

  bool get _hasAcceptedApplicant =>
      widget.applications.any((a) => a.status == JobApplicationStatus.accepted);

  /// Mirrors the backend's own JOB_015 check — cancellable at any point in
  /// the lifecycle except once it's already been terminated some other
  /// way (admin-rejected or already cancelled once).
  bool get _canCancel =>
      !widget.requirement.isCancelled &&
      widget.requirement.rejectionReason == null;

  /// Mirrors the backend's own JOB_017 check — only a requirement this
  /// account cancelled itself can be self-reactivated; an admin-rejected
  /// one never can (same asymmetry as _canCancel above).
  bool get _canReactivate => widget.requirement.isCancelled;

  /// Mirrors the backend's own JOB_014 check (job_applications.status IN
  /// ('applied', 'accepted')) — editing is blocked once a caregiver has
  /// responded, regardless of the requirement's own status. Rejected/
  /// completed applications never count.
  bool get _hasActiveApplication => widget.applications.any((a) =>
      a.status == JobApplicationStatus.applied ||
      a.status == JobApplicationStatus.accepted);

  String get _statusLabel {
    switch (widget.requirement.status) {
      case JobStatus.pendingReview:
        return 'Pending admin review';
      case JobStatus.active:
        return 'Live — visible to caregivers';
      case JobStatus.closed:
        if (widget.requirement.isCancelled) return 'Cancelled';
        if (widget.requirement.rejectionReason != null) return 'Rejected';
        return _hasAcceptedApplicant ? 'Closed — caregiver assigned' : 'Closed';
      default:
        return widget.requirement.status;
    }
  }

  Color get _statusColor {
    switch (widget.requirement.status) {
      case JobStatus.pendingReview:
        return AppColors.warning;
      case JobStatus.active:
        return AppColors.success;
      case JobStatus.closed:
        if (widget.requirement.isCancelled) return AppColors.textSecondary;
        return widget.requirement.rejectionReason != null
            ? AppColors.error
            : AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  /// The card's own outer border — red while the job is genuinely live
  /// (active, visible to caregivers right now), grey once it's cancelled
  /// or closed in any way (including pending_review, which isn't yet
  /// visible to caregivers). A different signal from [_statusColor], which
  /// colors the status pill itself.
  Color get _cardBorderColor =>
      widget.requirement.status == JobStatus.active ? AppColors.error : AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final requirement = widget.requirement;
    final careReceiver = requirement.careReceiver;
    final locked = _hasActiveApplication;
    // A fixed 2-item menu, always offered — each item individually
    // disabled (not hidden) when its own precondition doesn't hold, so the
    // set of actions is always predictable rather than shifting around
    // based on state. The second slot is Reactivate (not Cancel) once the
    // requirement is cancelled — cancelling an already-cancelled one makes
    // no sense, but bringing it back does.
    final menuActions = <_MenuAction>[
      _MenuAction(
        label: locked ? 'Edit the Job (Locked)' : 'Edit the Job',
        enabled: !locked,
        onSelected: widget.onEdit,
      ),
      if (widget.requirement.isCancelled)
        _MenuAction(
          label: 'Make Active Again',
          enabled: _canReactivate,
          onSelected: widget.onReactivate,
        )
      else
        _MenuAction(
          label: _canCancel ? 'Cancel the Job' : 'Cancel the Job (Unavailable)',
          enabled: _canCancel,
          destructive: true,
          onSelected: widget.onCancel,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      // A wide border on a light green shade — easier for a senior citizen
      // to see and tell apart from the page background/other cards than
      // the default thin light-grey outline used elsewhere. Red while the
      // job is genuinely live (see _cardBorderColor), grey once it's
      // cancelled or closed — so the border itself signals whether this
      // posting still needs attention.
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _cardBorderColor, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The status badge sits right next to the Job Id (small
              // margin between them) in a Wrap, not squeezed into a
              // Flexible sharing the row with the menu button — a Wrap
              // moves the badge onto its own second line when the row
              // genuinely has no room, rather than truncating a long label
              // like "Live — visible to caregivers" with "…".
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _JobIdLine(requirement: requirement),
                    _StatusBadge(
                      label: _statusLabel,
                      color: _statusColor,
                      blink: requirement.status == JobStatus.active,
                    ),
                  ],
                ),
              ),
              // Always exactly 2 actions — Edit / Cancel — each individually
              // disabled (not hidden) when its own precondition doesn't
              // hold, so the set of actions is predictable rather than
              // shifting around based on state.
              PopupMenuButton<_MenuAction>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (action) => action.onSelected(),
                itemBuilder: (context) => [
                  for (final action in menuActions)
                    PopupMenuItem<_MenuAction>(
                      value: action,
                      enabled: action.enabled,
                      child: Text(
                        action.label,
                        style: action.destructive && action.enabled
                            ? const TextStyle(color: AppColors.error)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (requirement.status == JobStatus.closed &&
              requirement.rejectionReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Reason: ${requirement.rejectionReason}',
                style: const TextStyle(color: AppColors.error)),
          ],
          // A clean, uniform label/value record — consistent font
          // size/weight/color across every line (matching clinical/hospital
          // documentation conventions).
          const SizedBox(height: AppSpacing.sm),
          if (careReceiver != null)
            _FieldLine(
              label: 'Type Of Care',
              value: CareTier.displayNames[deriveCareTier(careReceiver)] ?? deriveCareTier(careReceiver),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (careReceiver != null) ...[
                Expanded(
                  child: _FieldLine(
                    label: 'Scope Of Work',
                    value: 'Click Here',
                    isLink: true,
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => ScopeOfWorkDialog(
                        tier: deriveCareTier(careReceiver),
                        repository: ref.read(scopeOfWorkRepositoryProvider),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: _FieldLine(
                  label: 'Duty Requirements',
                  value: 'Click Here',
                  isLink: true,
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => DutyRequirementsDialog(
                      dutyType: requirement.dutyType,
                      repository: ref.read(dutyRequirementsRepositoryProvider),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _FieldLine(
            label: 'Salary Guidance Range',
            value: requirement.salaryAmount != null
                ? '₹${requirement.salaryAmount}/${requirement.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}'
                : 'Not set',
            valueColor: AppColors.error,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _detailsExpanded = !_detailsExpanded),
              icon: Icon(
                  _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(
                  _detailsExpanded ? 'Hide Full Details' : 'Show Full Details'),
            ),
          ),
          if (_detailsExpanded) ...[
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            // Labeled rows grouped under the same two headings as the
            // Post/Edit Requirement form (Patient Details / Care
            // Preferences), in the same field order — so what a patient
            // sees here when reviewing matches what they filled in when
            // posting, instead of an undifferentiated wall of chips where
            // e.g. a bare "Male" tag couldn't say whether it meant the
            // patient's own gender or a caregiver preference.
            if (careReceiver != null) ...[
              const _SectionLabel('Patient Details'),
              const SizedBox(height: AppSpacing.xs),
              _DetailRow('Age', '${careReceiver.age} yrs'),
              _DetailRow('Gender', _capitalize(careReceiver.gender)),
              _DetailRow('Weight', '${careReceiver.weightKg} kg'),
              _DetailRow('City',
                  City.displayNames[requirement.city] ?? requirement.city),
              if (requirement.area != null && requirement.area!.isNotEmpty)
                _DetailRow('Area', requirement.area!),
              _DetailRow(
                'Medical Condition',
                careReceiver.hasMedicalCondition &&
                        careReceiver.medicalConditions.isNotEmpty
                    ? careReceiver.medicalConditions
                        .map((c) => MedicalCondition.displayNames[c] ?? c)
                        .join(', ')
                    : 'None',
              ),
              if (careReceiver.medicalConditionOther != null &&
                  careReceiver.medicalConditionOther!.isNotEmpty)
                _DetailRow(
                    'Other Condition', careReceiver.medicalConditionOther!),
              const SizedBox(height: AppSpacing.md),
            ],
            const _SectionLabel('Care Preferences'),
            const SizedBox(height: AppSpacing.xs),
            _DetailRow(
                'Hours Care Needed',
                DutyType.displayNames[requirement.dutyType] ??
                    requirement.dutyType),
            if (requirement.startDate != null)
              _DetailRow('Preferred Start Date', requirement.startDate!),
            if (requirement.careDuration != null)
              _DetailRow(
                'Duration Care is Needed',
                CareDuration.displayNames[requirement.careDuration] ??
                    requirement.careDuration!,
              ),
            if (careReceiver != null) ...[
              _DetailRow(
                'Toilet Assistance',
                careReceiver.toiletAssistance.isEmpty
                    ? 'None'
                    : careReceiver.toiletAssistance
                        .map((t) => ToiletAssistance.displayNames[t] ?? t)
                        .join(', '),
              ),
              if (careReceiver.toiletAssistanceOther != null &&
                  careReceiver.toiletAssistanceOther!.isNotEmpty)
                _DetailRow('Other Toilet Assistance',
                    careReceiver.toiletAssistanceOther!),
              _DetailRow(
                'Feeding/Medicine Assistance',
                FeedingType.displayNames[careReceiver.feedingType] ??
                    careReceiver.feedingType,
              ),
            ],
            _DetailRow(
              'Preferred Caregiver Gender',
              requirement.preferredGender != null
                  ? _capitalize(requirement.preferredGender!)
                  : 'No preference',
            ),
            const SizedBox(height: AppSpacing.md),
            const _SectionLabel('Nurse Fee Guidance'),
            const SizedBox(height: AppSpacing.xs),
            _DetailRow(
              'Frequency of Care',
              requirement.frequencyOfCare != null
                  ? FrequencyOfCare.displayNames[requirement.frequencyOfCare] ??
                      requirement.frequencyOfCare!
                  : 'Not set',
            ),
            _DetailRow(
              'Salary',
              requirement.salaryAmount != null
                  ? '₹${requirement.salaryAmount}/${requirement.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}'
                  : 'Not set',
            ),
            if (requirement.description != null &&
                requirement.description!.isNotEmpty)
              _DetailRow('More Details', requirement.description!),
          ],
          if (requirement.status != JobStatus.pendingReview) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (requirement.isCancelled)
              const Text(
                'This requirement was cancelled. Candidate applications are no longer available.',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              )
            else
              _ApplicantsSection(
                applications: widget.applications,
                decidingApplicationId: widget.decidingApplicationId,
                onAccept: widget.onAccept,
                onReject: widget.onReject,
                onViewProfile: widget.onViewProfile,
              ),
          ],
        ],
      ),
    );
  }
}

/// A prominent, plain-language, color-coded status pill — the single most
/// important thing to communicate at a glance, especially for a senior
/// citizen scanning the card quickly.
/// [blink] is only ever true while the job is genuinely live (active,
/// visible to caregivers right now) — same "needs attention" signal as
/// the card's own red border (_cardBorderColor) and JobDetailCard's
/// BlinkingStartDateBadge on the caregiver-facing side.
class _StatusBadge extends StatefulWidget {
  final String label;
  final Color color;
  final bool blink;

  const _StatusBadge({required this.label, required this.color, this.blink = false});

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(_controller);
    if (widget.blink) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        border: Border.all(color: widget.color, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      // No overflow/ellipsis — a status label wraps onto a second line
      // rather than ever being truncated with "…"; the pill's own
      // rounded-rect background grows with it (borderRadius 999 still
      // reads as fully rounded ends on a short one-line label, and as a
      // softly rounded rectangle on a wrapped two-line one).
      child: Text(widget.label,
          style: TextStyle(
              color: widget.color, fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle)),
    );
    if (!widget.blink) return badge;
    return FadeTransition(opacity: _opacity, child: badge);
  }
}

/// A single "More options" menu action — [enabled] mirrors the same
/// preconditions the old primary-button/secondary-menu split used to
/// enforce (JOB_014 for editing, the one-live-requirement rule for Post
/// Similar, JOB_015 for cancelling), just always rendered as one of a
/// fixed 3-item menu rather than conditionally shown/hidden.
class _MenuAction {
  final String label;
  final bool enabled;
  final bool destructive;
  final VoidCallback onSelected;

  const _MenuAction({
    required this.label,
    required this.enabled,
    this.destructive = false,
    required this.onSelected,
  });
}

// The label portion (before the colon) of every field line — "Job Id",
// "Type Of Care", "Salary Guidance Range", "Scope Of Work", "Duty
// Requirements" — is bold black, distinct from the dark green value that
// follows it.
const _fieldLabelStyle = TextStyle(
    fontSize: AppTypography.body, color: AppColors.textPrimary, fontWeight: FontWeight.bold);
const _fieldValueStyle = TextStyle(
    fontSize: AppTypography.body, color: AppColors.success, fontWeight: FontWeight.bold);
const _fieldLinkStyle = TextStyle(
    fontSize: AppTypography.body,
    color: AppColors.success,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline);

/// The card's primary identifier — the job's real display id, set apart
/// from the "Job Id" label (bold black, like every other field label) in
/// its own larger bold green, same visual weight a hospital chart gives a
/// record/MRN number.
class _JobIdLine extends StatelessWidget {
  final JobModel requirement;

  const _JobIdLine({required this.requirement});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Job Id: ', style: _fieldLabelStyle),
          TextSpan(
            text: jobDisplayId(requirement),
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
/// of Work or Duty Requirements popup). Consistent font size/weight/color
/// across every line of this shape, so the card reads like a clean record
/// rather than a mix of ad hoc chip styles.
class _FieldLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isLink;
  final VoidCallback? onTap;
  // Overrides the value's color only — e.g. the Salary Guidance Range
  // figure stays red regardless of the shared dark-green value color every
  // other field line uses, to draw the eye straight to the number.
  final Color? valueColor;

  const _FieldLine({
    required this.label,
    required this.value,
    this.isLink = false,
    this.onTap,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final baseValueStyle = isLink ? _fieldLinkStyle : _fieldValueStyle;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: _fieldLabelStyle),
          TextSpan(
            text: value,
            style: valueColor != null
                ? baseValueStyle.copyWith(color: valueColor)
                : baseValueStyle,
          ),
        ],
      ),
    );
    if (onTap == null) return text;
    return InkWell(onTap: onTap, child: text);
  }
}

/// Shows the total applicant count up front, then every applicant — no
/// candidate's profile/phone is ever hidden, whichever side rejected them
/// (or if the caregiver closed an accepted engagement themselves): the
/// patient/family can always look them up and reconsider. At most one
/// candidate can be `accepted` at a time (JOB_016 backstops this
/// server-side) — the accepted one is pinned to the top; while anyone is
/// accepted, no other candidate offers an Accept action (not even a
/// candidate this account or the caregiver had previously rejected) until
/// that acceptance is undone. Rejecting (declining an undecided candidate,
/// or undoing an acceptance) always requires a reason — see
/// _rejectWithReason.
class _ApplicantsSection extends StatelessWidget {
  final List<JobApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId) onAccept;
  final void Function(String applicationId) onReject;
  final void Function(String applicationId) onViewProfile;

  const _ApplicantsSection({
    required this.applications,
    required this.decidingApplicationId,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final hasAccepted =
        applications.any((a) => a.status == JobApplicationStatus.accepted);
    final awaitingCount = applications
        .where((a) => a.status == JobApplicationStatus.applied)
        .length;

    // Accepted candidate first (the one engagement that matters most right
    // now), then everyone else by most recent activity.
    final sorted = List<JobApplicationModel>.of(applications)
      ..sort((a, b) {
        final aAccepted = a.status == JobApplicationStatus.accepted;
        final bAccepted = b.status == JobApplicationStatus.accepted;
        if (aAccepted != bAccepted) return aAccepted ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '${applications.length} candidate${applications.length == 1 ? '' : 's'} applied in total',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        if (applications.isEmpty)
          const Text('No applicants yet.',
              style: TextStyle(color: AppColors.textSecondary))
        else ...[
          if (hasAccepted)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'You have accepted a candidate. Reject them to be able to accept someone else.',
                style: TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            )
          else if (awaitingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                awaitingCount == 1
                    ? '1 candidate awaiting your decision'
                    : '$awaitingCount candidates awaiting your decision',
                style: const TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            ),
          for (final application in sorted) ...[
            _ApplicantTile(
              application: application,
              isDeciding: decidingApplicationId.contains(application.id),
              // A completed engagement (the caregiver closed the job
              // themselves after finishing the work) can still be
              // re-accepted — "Accept Anyway", same as a previously
              // rejected candidate — since completeJob already reopens the
              // job to active server-side, there's nothing left to undo
              // first. Anyone already accepted obviously can't be accepted
              // again via this button (see _isAccepted below — Reject-to-
              // undo is the only action offered for them instead), and
              // while someone else is accepted, no one else is offered
              // Accept at all.
              canAccept: !hasAccepted,
              // An undecided candidate is only actionable (accept OR
              // reject) while no one else is accepted — once someone is,
              // the rest are simply on hold, not something you need to
              // actively decline. The currently-accepted candidate's own
              // Reject (undo) always stays available regardless.
              canReject: (application.status == JobApplicationStatus.applied &&
                      !hasAccepted) ||
                  application.status == JobApplicationStatus.accepted,
              onAccept: () => onAccept(application.id),
              onReject: () => onReject(application.id),
              onViewProfile: () => onViewProfile(application.id),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

class _ApplicantTile extends StatelessWidget {
  final JobApplicationModel application;
  final bool isDeciding;
  final bool canAccept;
  final bool canReject;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onViewProfile;

  const _ApplicantTile({
    required this.application,
    required this.isDeciding,
    required this.canAccept,
    required this.canReject,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
  });

  bool get _isAccepted => application.status == JobApplicationStatus.accepted;
  bool get _isApplied => application.status == JobApplicationStatus.applied;
  bool get _isCompleted => application.status == JobApplicationStatus.completed;
  bool get _isRejected => application.status == JobApplicationStatus.rejected;

  /// A rejected application with no decider is a caregiver's own
  /// withdrawal (closing a job they applied to before being accepted) —
  /// same `decided_by IS NULL` convention used everywhere else to tell a
  /// self-action apart from the patient's own decision.
  bool get _isRejectedByCaregiver =>
      _isRejected && application.decidedBy == null;

  String get _statusLabel {
    if (_isAccepted) return 'Accepted';
    if (_isApplied) return 'Awaiting your decision';
    if (_isCompleted) return 'Closed by Caregiver';
    if (_isRejectedByCaregiver) return 'Rejected by Caregiver';
    return _capitalize(application.status);
  }

  Color get _statusColor {
    if (_isAccepted) return AppColors.success;
    if (_isApplied) return AppColors.warning;
    if (_isRejected) return AppColors.error;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _isAccepted
            ? AppColors.success.withValues(alpha: 0.08)
            : _isApplied
                ? AppColors.warning.withValues(alpha: 0.08)
                : (_isRejected
                    ? AppColors.error.withValues(alpha: 0.06)
                    : null),
        // Amber/highlighted with a wider border — a candidate waiting on a
        // decision stands out from a plain grey/green/red decided tile at
        // a glance.
        border: Border.all(
          color: _isApplied
              ? AppColors.warning
              : (_statusColor == AppColors.textSecondary
                  ? AppColors.border
                  : _statusColor),
          width: _isApplied ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(application.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (_isAccepted) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.check_circle,
                          color: AppColors.success, size: 16),
                    ] else if (_isApplied) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.hourglass_top,
                          color: AppColors.warning, size: 16),
                    ] else if (_isRejected) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.cancel,
                          color: AppColors.error, size: 16),
                    ],
                  ],
                ),
              ),
              // Capped (not a competing-flex Expanded/Flexible) so it's
              // processed as a plain trailing child — Row gives the
              // Expanded name above ALL remaining space once this is
              // subtracted, which pins the status flush to the tile's
              // right edge rather than splitting the row 50/50. The cap
              // itself is what keeps this safe on a narrow tile: without
              // one, a long label (e.g. "Awaiting your decision") has no
              // bound at all in a Row and can overflow outright.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  _statusLabel,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: (_isAccepted || _isRejected)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          // The phone number and profile stay visible no matter the
          // outcome — rejected (by either side) or completed candidates
          // are never hidden, so the patient/family can always look them
          // up again and reconsider.
          Text(application.phone,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          _ApplicantTimeline(application),
          const SizedBox(height: AppSpacing.xs),
          if (isDeciding)
            const SizedBox(
                height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: onViewProfile,
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('View Profile'),
                ),
                // Expanded + Align(centerRight), not a Spacer()+Flexible
                // pair — a Spacer and a Flexible are BOTH flex children, so
                // Flutter splits the leftover space 50/50 between them
                // regardless of how little the button group actually
                // needs, leaving it short of the tile's true right edge
                // (the same bug the status label above had before it was
                // fixed). A single Expanded absorbing everything, with
                // Align pinning its child to that region's right edge,
                // lines this group up with the status label directly above
                // it. Align also gives the Wrap inside a real bounded
                // width, so it still drops Accept/Reject to their own
                // second line rather than overflow if the tile is too
                // narrow to fit everything on one line.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (canAccept)
                          TextButton.icon(
                            onPressed: onAccept,
                            icon: const Icon(Icons.check, size: 16, color: AppColors.success),
                            label: Text(
                              (_isRejected || _isCompleted) ? 'Accept Anyway' : 'Accept',
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: const TextStyle(color: AppColors.success),
                            ),
                          ),
                        if (canReject)
                          TextButton.icon(
                            onPressed: onReject,
                            icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                            label: const Text('Reject', style: TextStyle(color: AppColors.error)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The candidate's full action history on this application — every
/// transition with who did it and exactly when, newest first (the current
/// status is the one worth seeing without scrolling). `decidedByName`, when
/// present, names exactly who accepted/rejected — the patient/family
/// themselves, or an admin who intervened on their behalf via admin-web —
/// rather than a vague "you"/"the employer". A caregiver-initiated close
/// or self-withdrawal (`decidedBy == null`) is always the caregiver's own
/// doing, so those lines never need a name.
class _ApplicantTimeline extends StatefulWidget {
  final JobApplicationModel application;

  const _ApplicantTimeline(this.application);

  @override
  State<_ApplicantTimeline> createState() => _ApplicantTimelineState();
}

class _ApplicantTimelineState extends State<_ApplicantTimeline> {
  // Same fixed per-row heights as caregiver-app's own ApplicationTimeline
  // (job_detail_card.dart) — both parties see the same "4 rows by default,
  // scroll for the rest" treatment.
  static const _fontSize = AppTypography.small;
  static const _rowHeight = 18.0;
  static const _reasonRowHeight = 32.0; // a "Rejected + Reason" row wraps to two lines
  // Strictly less than 5 plain rows and strictly more than 4, so a 5th
  // entry always genuinely overflows and the scrollbar is never shown
  // without something real to scroll to.
  static const _maxHeight = 78.0;

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
      entries.add(MapEntry(at, 'Applied: ${_formatDateTime(at)}'));
    }
    if (application.acceptedAt != null) {
      final at = DateTime.parse(application.acceptedAt!).toLocal();
      final by = application.decidedByName != null
          ? ' by ${application.decidedByName}'
          : '';
      entries.add(MapEntry(at, 'Accepted$by: ${_formatDateTime(at)}'));
    }
    // Shown whenever completedAt is set, regardless of the application's
    // CURRENT status — e.g. still shown as history after the candidate is
    // later accepted again ("Accept Anyway") or re-applies, neither of
    // which clear completedAt any more (see
    // OrganisationRequirementApplicationsRepository.upsert/decide).
    if (application.completedAt != null) {
      final at = DateTime.parse(application.completedAt!).toLocal();
      var text = 'Closed by Caregiver: ${_formatDateTime(at)}';
      if (application.closeReason != null) {
        text = '$text\nReason: ${CaregiverCloseReason.displayNames[application.closeReason] ?? application.closeReason}';
      }
      entries.add(MapEntry(at, text));
    }
    // Shown whenever rejectedAt is set, regardless of the application's
    // CURRENT status — same reasoning as completedAt above, so a
    // previously-declined-then-accepted-anyway (or re-applied) candidate's
    // rejection stays visible as history instead of silently vanishing.
    if (application.rejectedAt != null) {
      final at = DateTime.parse(application.rejectedAt!).toLocal();
      final label = application.decidedByName != null
          ? 'Rejected by ${application.decidedByName}'
          : 'Rejected by Caregiver';
      var text = '$label: ${_formatDateTime(at)}';
      if (application.declineReason != null &&
          application.declineReason!.isNotEmpty) {
        text = '$text\nReason: ${application.declineReason!}';
      }
      entries.add(MapEntry(at, text));
    }
    // A candidate can re-apply, then be decided on again — shown last since
    // it always comes after whatever prior outcome it followed.
    if (application.reappliedAt != null) {
      final at = DateTime.parse(application.reappliedAt!).toLocal();
      entries.add(MapEntry(at, 'Re-applied: ${_formatDateTime(at)}'));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    // Newest first — the current status is the one worth seeing without
    // having to scroll for it, same convention as caregiver-app's own
    // ApplicationTimeline.
    entries.sort((a, b) => b.key.compareTo(a.key));

    final totalHeight = entries.fold<double>(
      0,
      (sum, entry) => sum + (entry.value.contains('\n') ? _reasonRowHeight : _rowHeight),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: Scrollbar(
        controller: _controller,
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
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: _fontSize),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
