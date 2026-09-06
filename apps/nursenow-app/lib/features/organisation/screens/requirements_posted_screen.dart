import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/icon_widgets.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../caregiver_profile/screens/caregiver_profile_view_screen.dart';
import 'post_organisation_requirement_screen.dart';
import 'edit_organisation_requirement_screen.dart';

/// An organisation's full requirement history — unlike Individual, there is
/// no one-live-at-a-time limit, so "Post a Requirement" is always
/// available and many requirements can be active simultaneously. See
/// "NurseNow" in CLAUDE.md.
class RequirementsPostedScreen extends ConsumerStatefulWidget {
  const RequirementsPostedScreen({super.key});

  @override
  ConsumerState<RequirementsPostedScreen> createState() => _RequirementsPostedScreenState();
}

class _RequirementsPostedScreenState extends ConsumerState<RequirementsPostedScreen> {
  bool _loading = true;
  String? _error;
  List<OrganisationRequirementModel> _requirements = [];
  Map<String, List<OrganisationRequirementApplicationModel>> _applicationsByRequirementId = {};
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
      final repo = ref.read(organisationRepositoryProvider);
      final requirements = await repo.listMyRequirements();
      final withApplications = requirements.where((r) => r.status != JobStatus.pendingReview).toList();
      final applicationLists = await Future.wait(withApplications.map((r) => repo.listApplications(r.id)));
      if (!mounted) return;
      setState(() {
        _requirements = requirements;
        _applicationsByRequirementId = {
          for (var i = 0; i < withApplications.length; i++) withApplications[i].id: applicationLists[i],
        };
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String requirementId, String applicationId) async {
    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(organisationRepositoryProvider).decideApplication(requirementId, applicationId, 'accepted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  /// A reason is mandatory (JOB_012 is the server-side backstop) — the
  /// dialog's Confirm button stays disabled until something is typed, so
  /// there's no way to submit a reject without one. Used both for declining
  /// an undecided candidate and for undoing a prior acceptance.
  Future<void> _rejectWithReason(String requirementId, String applicationId) async {
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
              onPressed:
                  controller.text.trim().isEmpty ? null : () => Navigator.of(dialogContext).pop(controller.text.trim()),
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
          .read(organisationRepositoryProvider)
          .decideApplication(requirementId, applicationId, 'rejected', reason: reason);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  /// Unlike Individual's forced one-at-a-time flow, Organisation's review
  /// is a free list — any applicant's profile can be viewed, not just one
  /// at a time.
  void _viewProfile(String requirementId, String applicationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaregiverProfileViewScreen(
          fetchProfile: () =>
              ref.read(organisationRepositoryProvider).getApplicantProfile(requirementId, applicationId),
        ),
      ),
    );
  }

  Future<void> _postRequirement() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostOrganisationRequirementScreen()),
    );
    if (posted == true) await _load();
  }

  /// Allowed regardless of the requirement's own status (pending_review/
  /// active/closed) — only gated on there being no active application, same
  /// as Individual's own EditRequirementScreen entry point.
  Future<void> _editRequirement(OrganisationRequirementModel requirement) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditOrganisationRequirementScreen(requirement: requirement)),
    );
    if (edited == true) await _load();
  }

  /// Allowed at any point in the requirement's lifecycle except once it's
  /// already been terminated some other way (admin-rejected or already
  /// cancelled once) — mirrors the backend's JOB_015. Cancelling only stops
  /// new applications from coming in — every candidate who already applied
  /// stays exactly as they were: still visible, still contactable, and can
  /// still be accepted or rejected afterward.
  Future<void> _cancelRequirement(OrganisationRequirementModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hide this job for new applications?'),
        content: const Text(
          'This stops new caregivers from applying. Candidates who already applied stay visible — '
          'you can still view their profile and accept or reject them afterward. You can unhide and make '
          'it live again anytime.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('No, keep it live')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, hide it', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(organisationRepositoryProvider).cancelRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Only offered once a requirement has actually been cancelled (mirrors
  /// the backend's own JOB_017 check) — brings it back to active without
  /// needing admin to re-review, since admin's original approval already
  /// vetted the content and cancelling never meant more than "stop taking
  /// new applications for now".
  Future<void> _reactivateRequirement(OrganisationRequirementModel requirement) async {
    try {
      await ref.read(organisationRepositoryProvider).reactivateRequirement(requirement.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Pre-fills a new posting from a past requirement's fields — unlike
  /// Individual, there is no one-live-limit to gate this on, so it's always
  /// offered.
  Future<void> _postSimilarRequirement(OrganisationRequirementModel requirement) async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PostOrganisationRequirementScreen(cloneFrom: requirement)),
    );
    if (posted == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isJobPostingBlocked = session is SessionAuthenticated && session.isJobPostingBlocked;

    return Scaffold(
      appBar: AppBar(title: const VitaAppBarTitle('Requirements Posted'), actions: const [WhatsAppHelpButton()]),
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
                    ElevatedButton.icon(
                      onPressed: isJobPostingBlocked ? null : _postRequirement,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Post a Requirement'),
                    ),
                    if (isJobPostingBlocked) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Posting is currently blocked. Contact the office for details.',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
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
                        _RequirementCard(
                          requirement: requirement,
                          applications: _applicationsByRequirementId[requirement.id] ?? const [],
                          decidingApplicationId: _decidingApplicationId,
                          onAccept: (applicationId) => _accept(requirement.id, applicationId),
                          onReject: (applicationId) => _rejectWithReason(requirement.id, applicationId),
                          onViewProfile: (applicationId) => _viewProfile(requirement.id, applicationId),
                          onEdit: () => _editRequirement(requirement),
                          onCancel: () => _cancelRequirement(requirement),
                          onReactivate: () => _reactivateRequirement(requirement),
                          onPostSimilar: () => _postSimilarRequirement(requirement),
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

/// A prominent, plain-language, color-coded status pill — the single most
/// important thing to communicate at a glance, instead of a plain colored
/// text label. Mirrors Individual's own _StatusBadge in jobs_posted_screen
/// .dart exactly (same pill shape/blink behavior), duplicated here since
/// the two screens' widgets aren't shared. [blink] is only ever true while
/// the requirement is genuinely live (active, visible to caregivers right
/// now) — same "needs attention" signal as the card's own red border
/// (_cardBorderColor).
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12),
        border: Border.all(color: widget.color, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      // Always a single line — never wraps onto a second line; truncated
      // with "…" only in the extreme case where the row genuinely has no
      // room left for it (see the Flexible wrapping this badge).
      child: Text(widget.label,
          textAlign: TextAlign.end,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: widget.color, fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle)),
    );
    if (!widget.blink) return badge;
    return FadeTransition(opacity: _opacity, child: badge);
  }
}

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
        child: Text(label, style: const TextStyle(fontSize: AppTypography.small)),
      ),
    );
  }
}

class _RequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final List<OrganisationRequirementApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId) onAccept;
  final void Function(String applicationId) onReject;
  final void Function(String applicationId) onViewProfile;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onReactivate;
  final VoidCallback onPostSimilar;

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
    required this.onPostSimilar,
  });

  bool get _hasAcceptedApplicant => applications.any((a) => a.status == JobApplicationStatus.accepted);

  int get _acceptedCount => applications.where((a) => a.status == JobApplicationStatus.accepted).length;

  /// Mirrors the backend's own JOB_015 check — cancellable at any point in
  /// the lifecycle except once it's already been terminated some other way
  /// (admin-rejected or already cancelled once).
  bool get _canCancel => !requirement.isCancelled && requirement.rejectionReason == null;

  /// Mirrors the backend's own JOB_014 check — editing is blocked the
  /// moment ANY caregiver has ever applied, regardless of the requirement's
  /// own status or that application's own status (applied/accepted/
  /// rejected/completed all lock it) — a deliberately stricter rule than
  /// the jobs pipeline's own edit lock.
  bool get _hasAnyApplication => applications.isNotEmpty;

  String get _statusLabel {
    switch (requirement.status) {
      case JobStatus.pendingReview:
        return 'Pending admin review';
      case JobStatus.active:
        return 'Live — visible to caregivers';
      case JobStatus.closed:
        if (requirement.isCancelled) return 'Hidden';
        if (requirement.rejectionReason != null) return 'Rejected';
        return _hasAcceptedApplicant ? 'Closed — caregiver assigned' : 'Closed';
      default:
        return requirement.status;
    }
  }

  Color get _statusColor {
    switch (requirement.status) {
      case JobStatus.pendingReview:
        return AppColors.warning;
      case JobStatus.active:
        return AppColors.success;
      case JobStatus.closed:
        if (requirement.isCancelled) return AppColors.textSecondary;
        return requirement.rejectionReason != null ? AppColors.error : AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Red while the requirement is genuinely live (active, visible to
  /// caregivers right now), grey once it's pending review, closed, or
  /// rejected — same convention as nursenow's Jobs Posted card.
  Color get _cardBorderColor => requirement.status == JobStatus.active ? AppColors.error : AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final locked = _hasAnyApplication;
    // A fixed 4-item menu, always offered — each item individually
    // disabled (not hidden) when its own precondition doesn't hold, so the
    // set of actions is predictable rather than shifting around based on
    // state. Unlike Individual, Post Similar Requirement is never gated —
    // an organisation has no one-live-at-a-time limit. Hide/Unhide are
    // listed first — the two most commonly reached-for actions — above
    // Edit and Post Similar Requirement.
    final menuActions = <_MenuAction>[
      _MenuAction(
        label: _canCancel ? 'Hide Job for New Applications' : 'Hide Job for New Applications (Unavailable)',
        enabled: _canCancel,
        destructive: true,
        onSelected: onCancel,
      ),
      // Only enabled once actually hidden (mirrors the backend's own
      // JOB_017 check) — brings it back to active without needing admin to
      // re-review, since admin's original approval already vetted the
      // content and hiding never meant more than "stop taking new
      // applications for now".
      _MenuAction(
        label: requirement.isCancelled ? 'Unhide and Make it Live' : 'Unhide and Make it Live (Unavailable)',
        enabled: requirement.isCancelled,
        onSelected: onReactivate,
      ),
      _MenuAction(
        label: locked ? 'Edit the Requirement (Locked)' : 'Edit the Requirement',
        enabled: !locked,
        onSelected: onEdit,
      ),
      _MenuAction(label: 'Post Similar Requirement', enabled: true, onSelected: onPostSimilar),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: _cardBorderColor, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The status badge sits right next to the requirement id
              // (small margin between them) in a Wrap, not squeezed into a
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
                    Text(organisationJobDisplayId(requirement),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                    _StatusBadge(
                      label: _statusLabel,
                      color: _statusColor,
                      blink: requirement.status == JobStatus.active,
                    ),
                  ],
                ),
              ),
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
          if (requirement.status == JobStatus.closed && requirement.rejectionReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Reason: ${requirement.rejectionReason}', style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.sm),
          IconField(
            icon: Icons.medical_services,
            text: requirement.typeOfNurse == TypeOfNurse.others && requirement.typeOfNurseOther != null
                ? '${TypeOfNurse.displayNames[requirement.typeOfNurse]}: ${requirement.typeOfNurseOther}'
                : TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            children: [
              if (requirement.durationType != null)
                _Tag(RequirementDuration.displayNames[requirement.durationType] ?? requirement.durationType!),
              _Tag(requirement.accommodationProvided ? 'Accommodation provided' : 'No accommodation'),
              _Tag(requirement.foodProvided ? 'Food provided' : 'No food'),
              _Tag('Vacancies: ${requirement.numberOfVacancies}'),
              if (requirement.preferredGender != null)
                _Tag('Preferred: ${Gender.displayNames[requirement.preferredGender] ?? requirement.preferredGender}'),
            ],
          ),
          if (requirement.specialSkills != null && requirement.specialSkills!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(requirement.specialSkills!,
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
          ],
          if (requirement.status != JobStatus.pendingReview) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Text('Applicants (${applications.length}) — ${requirement.numberOfVacancies} vacanc'
                '${requirement.numberOfVacancies == 1 ? 'y' : 'ies'}, $_acceptedCount accepted',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
            const SizedBox(height: AppSpacing.sm),
            if (applications.isEmpty)
              const Text('No applicants yet.', style: TextStyle(color: AppColors.textSecondary))
            else
              for (final application in applications) ...[
                _ApplicantTile(
                  application: application,
                  isDeciding: decidingApplicationId.contains(application.id),
                  // Any number of candidates can be accepted onto the same
                  // requirement at once — number_of_vacancies is purely
                  // informational (what the org told caregivers it's hiring
                  // for), never an accept cap. Every candidate not already
                  // accepted (applied, rejected, or completed) always offers
                  // an Accept action.
                  canAccept: application.status != JobApplicationStatus.accepted,
                  canReject: application.status == JobApplicationStatus.applied ||
                      application.status == JobApplicationStatus.accepted,
                  onAccept: () => onAccept(application.id),
                  onReject: () => onReject(application.id),
                  onViewProfile: () => onViewProfile(application.id),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        ],
      ),
    );
  }
}

class _ApplicantTile extends StatelessWidget {
  final OrganisationRequirementApplicationModel application;
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
  bool get _isRejected => application.status == JobApplicationStatus.rejected;
  bool get _isCompleted => application.status == JobApplicationStatus.completed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _isAccepted ? AppColors.success.withValues(alpha: 0.08) : null,
        border: Border.all(color: _isAccepted ? AppColors.success : AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(application.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (_isAccepted) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                        ],
                      ],
                    ),
                    Text(application.phone, style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (isDeciding) const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20)),
            ],
          ),
          const SizedBox(height: 2),
          // The full per-transition log — actor, action, date/time, and
          // reason (if any) — not just the bare current status word.
          _ApplicantTimeline(application),
          if (!isDeciding) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onViewProfile,
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: const Text('View Profile'),
                ),
                // "Accepted" stays visible even while the Reject (undo)
                // button is also offered — a currently-accepted candidate
                // is always both, unlike every other status which shows
                // exactly one of a status word or an action button.
                if (_isAccepted)
                  const Text('Accepted', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                if (canAccept)
                  TextButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check, size: 16, color: AppColors.success),
                    label: Text(
                      (_isRejected || _isCompleted) ? 'Accept Anyway' : 'Accept',
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
          ],
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// Seconds are included (not just hours:minutes) so two actions taken within
// the same minute — e.g. the org rejecting right after another applied —
// still display in a visibly distinguishable, correctly ordered sequence.
String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:'
    '${date.second.toString().padLeft(2, '0')}';

/// The full per-transition log for one applicant — actor, action, date/
/// time, and reason (if any), not just the bare current status word.
/// Mirrors Individual's own _ApplicantTimeline in jobs_posted_screen.dart
/// exactly (same entries/ordering), duplicated here since the two screens'
/// widgets aren't shared.
class _ApplicantTimeline extends StatelessWidget {
  final OrganisationRequirementApplicationModel application;

  const _ApplicantTimeline(this.application);

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<DateTime, String>>[];
    if (application.appliedAt != null) {
      final at = DateTime.parse(application.appliedAt!).toLocal();
      entries.add(MapEntry(at, 'Applied: ${_formatDateTime(at)}'));
    }
    if (application.acceptedAt != null) {
      final at = DateTime.parse(application.acceptedAt!).toLocal();
      final by = application.decidedByName != null ? ' by ${application.decidedByName}' : '';
      entries.add(MapEntry(at, 'Accepted$by: ${_formatDateTime(at)}'));
    }
    if (application.status == JobApplicationStatus.completed && application.completedAt != null) {
      final at = DateTime.parse(application.completedAt!).toLocal();
      var text = 'Closed by Caregiver: ${_formatDateTime(at)}';
      if (application.closeReason != null) {
        text = '$text\nReason: ${CaregiverCloseReason.displayNames[application.closeReason] ?? application.closeReason}';
      }
      entries.add(MapEntry(at, text));
    }
    if (application.status == JobApplicationStatus.rejected && application.rejectedAt != null) {
      final at = DateTime.parse(application.rejectedAt!).toLocal();
      final label = application.decidedByName != null ? 'Rejected by ${application.decidedByName}' : 'Rejected by Caregiver';
      var text = '$label: ${_formatDateTime(at)}';
      if (application.declineReason != null && application.declineReason!.isNotEmpty) {
        text = '$text\nReason: ${application.declineReason!}';
      }
      entries.add(MapEntry(at, text));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    // Newest first — the current status is the one worth seeing without
    // having to scroll for it, same convention as Individual's own
    // _ApplicantTimeline and caregiver-app's ApplicationTimeline.
    entries.sort((a, b) => b.key.compareTo(a.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              entry.value,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
            ),
          ),
      ],
    );
  }
}
