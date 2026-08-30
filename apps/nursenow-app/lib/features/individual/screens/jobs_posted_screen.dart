import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../app/rate_card_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../caregiver_profile/screens/caregiver_profile_view_screen.dart';
import 'edit_requirement_screen.dart';
import 'post_requirement_screen.dart';

/// Statuses that count as "live" for the one-live-requirement-at-a-time
/// rule (JOB_009 server-side) — a not-yet-approved pending_review posting
/// blocks a new one exactly the same as an already-active one.
bool _isLive(JobModel job) => job.status == JobStatus.pendingReview || job.status == JobStatus.active;

/// Full requirement history for this account — every past posting stays
/// visible (pending review / live / rejected / closed), not just the
/// current one, so a patient/family can always see who was accepted on a
/// past requirement even after it's closed. Posting a new requirement is
/// only blocked while a LIVE one exists (pending_review or active) — a
/// closed or rejected requirement never blocks posting again.
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
  // Past (closed/cancelled/rejected) requirements are hidden by default —
  // only the live one (if any) shows up-front — and revealed on demand via
  // a single toggle button, instead of cluttering the screen with every
  // past posting at once.
  bool _showClosed = false;

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
      final withApplications = requirements.where((r) => r.status != JobStatus.pendingReview).toList();
      final applicationLists = await Future.wait(withApplications.map((r) => repo.listApplications(r.id)));
      if (!mounted) return;
      setState(() {
        _requirements = requirements;
        _applicationsByJobId = {
          for (var i = 0; i < withApplications.length; i++) withApplications[i].id: applicationLists[i],
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
      await ref.read(individualRepositoryProvider).decideApplication(jobId, applicationId, JobApplicationStatus.accepted);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
            decoration: const InputDecoration(labelText: 'Reason (required, shown to no one but you)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref
          .read(individualRepositoryProvider)
          .decideApplication(jobId, applicationId, JobApplicationStatus.rejected, reason: reason);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
          fetchProfile: () => ref.read(individualRepositoryProvider).getApplicantProfile(jobId, applicationId),
        ),
      ),
    );
  }

  Future<void> _postRequirement() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostRequirementScreen()),
    );
    if (posted == true) await _load();
  }

  /// Allowed regardless of the requirement's own status (pending_review/
  /// active/closed) — only gated on there being no active application
  /// (see _RequirementCard._hasActiveApplication), matching the backend's
  /// own JOB_014 check.
  Future<void> _editRequirement(JobModel requirement) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditRequirementScreen(requirement: requirement)),
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
          "cancelled. You won't be able to see who applied afterward. This cannot be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('No, keep it')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, cancel it', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(individualRepositoryProvider).cancelRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Pre-fills a new posting from a past requirement's fields (see
  /// PostRequirementScreen.cloneFrom) — only offered once there's no
  /// current live requirement (mirrors the top Post CTA's own gating),
  /// since attempting it otherwise would just 409 with JOB_009 anyway.
  Future<void> _postSimilarRequirement(JobModel requirement) async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PostRequirementScreen(cloneFrom: requirement)),
    );
    if (posted == true) await _load();
  }

  /// Whether this requirement should surface up front rather than behind
  /// the "Show Closed/Cancelled Requirements" toggle — true for a live one
  /// (_isLive), but ALSO true for a closed one with a currently-accepted
  /// candidate: `status: closed` there just means "no longer accepting new
  /// applicants", not "this engagement is over" — a family with an actual
  /// caregiver assigned should still see it without digging through the
  /// closed/cancelled section. It only drops into that section once the
  /// engagement genuinely ends (rejected, or completed).
  bool _shouldShowUpFront(JobModel requirement) {
    if (_isLive(requirement)) return true;
    final applications = _applicationsByJobId[requirement.id] ?? const [];
    return applications.any((a) => a.status == JobApplicationStatus.accepted);
  }

  Widget _buildCard(JobModel requirement, bool hasLiveRequirement) {
    return _RequirementCard(
      requirement: requirement,
      applications: _applicationsByJobId[requirement.id] ?? const [],
      decidingApplicationId: _decidingApplicationId,
      canPostNew: !hasLiveRequirement,
      onAccept: (applicationId) => _accept(requirement.id, applicationId),
      onReject: (applicationId) => _rejectWithReason(requirement.id, applicationId),
      onViewProfile: (applicationId) => _viewProfile(requirement.id, applicationId),
      onEdit: () => _editRequirement(requirement),
      onCancel: () => _cancelRequirement(requirement),
      onPostSimilar: () => _postSimilarRequirement(requirement),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isJobPostingBlocked = session is SessionAuthenticated && session.isJobPostingBlocked;
    final hasLiveRequirement = _requirements.any(_isLive);
    final upFrontRequirements = _requirements.where(_shouldShowUpFront).toList();
    final closedRequirements = _requirements.where((r) => !_shouldShowUpFront(r)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs Posted'),
        actions: const [RateCardButton(), WhatsAppHelpButton()],
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
                    if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
                    if (!hasLiveRequirement) ...[
                      ElevatedButton(
                        onPressed: isJobPostingBlocked ? null : _postRequirement,
                        child: const Text('Post a Requirement'),
                      ),
                      if (isJobPostingBlocked) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Posting is currently blocked. Contact the office for details.',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (_requirements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          "You don't have any requirements posted yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else ...[
                      for (final requirement in upFrontRequirements) ...[
                        _buildCard(requirement, hasLiveRequirement),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (closedRequirements.isNotEmpty) ...[
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _showClosed = !_showClosed),
                          icon: Icon(_showClosed ? Icons.expand_less : Icons.expand_more),
                          label: Text(
                            _showClosed
                                ? 'Hide Closed/Cancelled Requirements'
                                : 'Show Closed/Cancelled Requirements (${closedRequirements.length})',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_showClosed)
                          for (final requirement in closedRequirements) ...[
                            _buildCard(requirement, hasLiveRequirement),
                            const SizedBox(height: AppSpacing.md),
                          ],
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _RequirementCard extends StatefulWidget {
  final JobModel requirement;
  final List<JobApplicationModel> applications;
  final Set<String> decidingApplicationId;
  /// Whether the account currently has no other live requirement — gates
  /// the "Post Similar Requirement" action, matching the top Post CTA.
  final bool canPostNew;
  final void Function(String applicationId) onAccept;
  final void Function(String applicationId) onReject;
  final void Function(String applicationId) onViewProfile;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onPostSimilar;

  const _RequirementCard({
    required this.requirement,
    required this.applications,
    required this.decidingApplicationId,
    required this.canPostNew,
    required this.onAccept,
    required this.onReject,
    required this.onViewProfile,
    required this.onEdit,
    required this.onCancel,
    required this.onPostSimilar,
  });

  @override
  State<_RequirementCard> createState() => _RequirementCardState();
}

class _RequirementCardState extends State<_RequirementCard> {
  bool _detailsExpanded = false;

  bool get _hasAcceptedApplicant =>
      widget.applications.any((a) => a.status == JobApplicationStatus.accepted);

  /// Mirrors the backend's own JOB_015 check — cancellable at any point in
  /// the lifecycle except once it's already been terminated some other
  /// way (admin-rejected or already cancelled once).
  bool get _canCancel => !widget.requirement.isCancelled && widget.requirement.rejectionReason == null;

  /// Mirrors the backend's own JOB_014 check (job_applications.status IN
  /// ('applied', 'accepted')) — editing is blocked once a caregiver has
  /// responded, regardless of the requirement's own status. Rejected/
  /// completed applications never count.
  bool get _hasActiveApplication => widget.applications
      .any((a) => a.status == JobApplicationStatus.applied || a.status == JobApplicationStatus.accepted);

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
        return widget.requirement.rejectionReason != null ? AppColors.error : AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirement = widget.requirement;
    final careReceiver = requirement.careReceiver;
    final locked = _hasActiveApplication;
    // Post Similar takes priority as the primary action once this
    // requirement is no longer the account's live one (posting fresh is
    // the more common next step than re-editing an old listing) — Edit is
    // then demoted to a secondary, tucked-away option. While locked (a
    // candidate is awaiting a decision), Edit isn't offered at all, even
    // as a secondary — only the one-line explanation is shown instead.
    final showPostSimilarPrimary = widget.canPostNew;
    final showEditPrimary = !showPostSimilarPrimary && !locked;
    final secondaryActions = <MapEntry<String, VoidCallback>>[
      if (_canCancel) MapEntry('Cancel Requirement', widget.onCancel),
      if (showPostSimilarPrimary && !locked) MapEntry('Edit', widget.onEdit),
    ];

    String? primaryLabel;
    IconData? primaryIcon;
    VoidCallback? primaryAction;
    if (showPostSimilarPrimary) {
      primaryLabel = 'Post Similar Requirement';
      primaryIcon = Icons.copy_outlined;
      primaryAction = widget.onPostSimilar;
    } else if (showEditPrimary) {
      primaryLabel = 'Edit';
      primaryIcon = Icons.edit;
      primaryAction = widget.onEdit;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      // A dark, wide border — easier for a senior citizen to see and tell
      // apart from the page background/other cards than the default thin
      // light-grey outline used elsewhere.
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textPrimary, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusBadge(label: _statusLabel, color: _statusColor),
                    const SizedBox(height: 4),
                    Text(
                      jobDisplayId(requirement),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Secondary, less-common actions are tucked behind a single
              // "More options" menu instead of always sitting on screen —
              // fewer buttons visible at once is easier to scan.
              if (secondaryActions.isNotEmpty)
                PopupMenuButton<VoidCallback>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    for (final action in secondaryActions)
                      PopupMenuItem<VoidCallback>(
                        value: action.value,
                        child: Text(
                          action.key,
                          style: action.key == 'Cancel Requirement' ? const TextStyle(color: AppColors.error) : null,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (requirement.status == JobStatus.closed && requirement.rejectionReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Reason: ${requirement.rejectionReason}', style: const TextStyle(color: AppColors.error)),
          ],
          if (requirement.status == JobStatus.active && requirement.salaryAmount != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '₹${requirement.salaryAmount}/${requirement.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${DutyType.displayNames[requirement.dutyType] ?? requirement.dutyType} in '
            '${City.displayNames[requirement.city] ?? requirement.city}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (primaryLabel != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: primaryAction,
                icon: Icon(primaryIcon, size: 18),
                label: Text(primaryLabel),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            )
          else if (locked)
            const Text(
              'Editing is locked while a candidate is awaiting your decision.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _detailsExpanded = !_detailsExpanded),
              icon: Icon(_detailsExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
              label: Text(_detailsExpanded ? 'Hide Full Details' : 'Show Full Details'),
            ),
          ),
          if (_detailsExpanded) ...[
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (careReceiver != null) ...[
              const _SectionLabel('About Patient'),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                children: [
                  _Tag('${careReceiver.age} yrs'),
                  _Tag(_capitalize(careReceiver.gender)),
                  _Tag('${careReceiver.weightKg} kg'),
                  _Tag(FeedingType.displayNames[careReceiver.feedingType] ?? careReceiver.feedingType),
                  for (final t in careReceiver.toiletAssistance)
                    _Tag('Toilet: ${ToiletAssistance.displayNames[t] ?? t}'),
                  if (careReceiver.hasMedicalCondition)
                    for (final c in careReceiver.medicalConditions) _Tag(MedicalCondition.displayNames[c] ?? c),
                ],
              ),
              if (careReceiver.medicalConditionOther != null && careReceiver.medicalConditionOther!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Other condition: ${careReceiver.medicalConditionOther!}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ],
              if (careReceiver.toiletAssistanceOther != null && careReceiver.toiletAssistanceOther!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Other toilet assistance: ${careReceiver.toiletAssistanceOther!}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            const _SectionLabel('Patient Care Requirement'),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              children: [
                _Tag(DutyType.displayNames[requirement.dutyType] ?? requirement.dutyType),
                // Always set on an active job (only ever null for a still
                // pending_review posting, which has no applicants section
                // shown at all — see below).
                if (requirement.frequencyOfCare != null)
                  _Tag(FrequencyOfCare.displayNames[requirement.frequencyOfCare!] ?? requirement.frequencyOfCare!),
                if (requirement.area != null && requirement.area!.isNotEmpty) _Tag(requirement.area!),
                if (requirement.startDate != null) _Tag('Start: ${requirement.startDate!}'),
                if (requirement.languages.isEmpty)
                  const _Tag('No Preference')
                else
                  for (final lang in requirement.languages) _Tag(Language.displayNames[lang] ?? lang),
                if (requirement.preferredGender != null) _Tag(_capitalize(requirement.preferredGender!)),
                if (requirement.preferredReligion != null)
                  _Tag(Religion.displayNames[requirement.preferredReligion] ?? requirement.preferredReligion!),
              ],
            ),
            if (requirement.description != null && requirement.description!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(requirement.description!),
            ],
          ],
          if (requirement.status != JobStatus.pendingReview) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (requirement.isCancelled)
              const Text(
                'This requirement was cancelled. Candidate applications are no longer available.',
                style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
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
class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
    );
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
    final hasAccepted = applications.any((a) => a.status == JobApplicationStatus.accepted);
    final awaitingCount = applications.where((a) => a.status == JobApplicationStatus.applied).length;

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
        Text('${applications.length} candidate${applications.length == 1 ? '' : 's'} applied in total',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        if (applications.isEmpty)
          const Text('No applicants yet.', style: TextStyle(color: AppColors.textSecondary))
        else ...[
          if (hasAccepted)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'You have accepted a candidate. Reject them to be able to accept someone else.',
                style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            )
          else if (awaitingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                awaitingCount == 1
                    ? '1 candidate awaiting your decision'
                    : '$awaitingCount candidates awaiting your decision',
                style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600),
              ),
            ),
          for (final application in sorted) ...[
            _ApplicantTile(
              application: application,
              isDeciding: decidingApplicationId.contains(application.id),
              // A completed engagement is a finished chapter (the caregiver
              // themselves closed it after actually doing the job) — not
              // reversible the way a plain rejection is, so it's excluded
              // from re-accept. Anyone already accepted obviously can't be
              // accepted again via this button (see _isAccepted below —
              // Reject-to-undo is the only action offered for them
              // instead), and while someone else is accepted, no one else
              // is offered Accept at all.
              canAccept: !hasAccepted && application.status != JobApplicationStatus.completed,
              // An undecided candidate is only actionable (accept OR
              // reject) while no one else is accepted — once someone is,
              // the rest are simply on hold, not something you need to
              // actively decline. The currently-accepted candidate's own
              // Reject (undo) always stays available regardless.
              canReject: (application.status == JobApplicationStatus.applied && !hasAccepted) ||
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
  bool get _isRejectedByCaregiver => _isRejected && application.decidedBy == null;

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
                : (_isRejected ? AppColors.error.withValues(alpha: 0.06) : null),
        // Amber/highlighted with a wider border — a candidate waiting on a
        // decision stands out from a plain grey/green/red decided tile at
        // a glance.
        border: Border.all(
          color: _isApplied ? AppColors.warning : (_statusColor == AppColors.textSecondary ? AppColors.border : _statusColor),
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
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (_isAccepted) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                    ] else if (_isApplied) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.hourglass_top, color: AppColors.warning, size: 16),
                    ] else if (_isRejected) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.cancel, color: AppColors.error, size: 16),
                    ],
                  ],
                ),
              ),
              Text(
                _statusLabel,
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: (_isAccepted || _isRejected) ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          // The phone number and profile stay visible no matter the
          // outcome — rejected (by either side) or completed candidates
          // are never hidden, so the patient/family can always look them
          // up again and reconsider.
          Text(application.phone, style: const TextStyle(color: AppColors.textSecondary)),
          // Full detail on a caregiver-initiated outcome — exactly when it
          // happened, alongside the name already shown above — so this
          // reads as e.g. "Rejected by <name>" / "Closed by <name>" with a
          // real timestamp, not just a bare status word. `updatedAt` is
          // always set and reflects the most recent transition on this row
          // (rejected_at/completed_at, whichever applies).
          if (_isCompleted || _isRejectedByCaregiver) ...[
            const SizedBox(height: 2),
            Text(
              '${_isCompleted ? 'Closed' : 'Rejected'}: '
              '${_formatDateTime(DateTime.parse(application.updatedAt).toLocal())}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
          // A candidate can re-apply, then be decided on again — this
          // shows the full history rather than just the latest outcome.
          if (application.reappliedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Re-applied: ${_formatDateTime(DateTime.parse(application.reappliedAt!).toLocal())}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
          if (_isRejected && application.declineReason != null && application.declineReason!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Your reason: ${application.declineReason!}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (isDeciding)
            const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
          else
            Row(
              children: [
                OutlinedButton(onPressed: onViewProfile, child: const Text('View Profile')),
                const Spacer(),
                if (canAccept)
                  TextButton(onPressed: onAccept, child: Text(_isRejected ? 'Accept Anyway' : 'Accept')),
                if (canReject)
                  TextButton(
                    onPressed: onReject,
                    child: Text('Reject', style: _isAccepted ? const TextStyle(color: AppColors.error) : null),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
