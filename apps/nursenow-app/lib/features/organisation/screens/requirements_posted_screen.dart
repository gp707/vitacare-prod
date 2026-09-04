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
        title: const Text('Cancel this requirement?'),
        content: const Text(
          'This stops new caregivers from applying. Candidates who already applied stay visible — '
          'you can still view their profile and accept or reject them afterward. This cannot be undone.',
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
      await ref.read(organisationRepositoryProvider).cancelRequirement(requirement.id);
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
    required this.onPostSimilar,
  });

  bool get _hasAcceptedApplicant => applications.any((a) => a.status == JobApplicationStatus.accepted);

  /// Mirrors the backend's own JOB_015 check — cancellable at any point in
  /// the lifecycle except once it's already been terminated some other way
  /// (admin-rejected or already cancelled once).
  bool get _canCancel => !requirement.isCancelled && requirement.rejectionReason == null;

  /// Mirrors the backend's own JOB_014 check — editing is blocked once a
  /// caregiver has responded, regardless of the requirement's own status.
  /// Rejected/completed applications never count.
  bool get _hasActiveApplication => applications.any(
      (a) => a.status == JobApplicationStatus.applied || a.status == JobApplicationStatus.accepted);

  String get _statusLabel {
    switch (requirement.status) {
      case JobStatus.pendingReview:
        return 'Pending admin review';
      case JobStatus.active:
        return 'Live — visible to caregivers';
      case JobStatus.closed:
        if (requirement.isCancelled) return 'Cancelled';
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
    final locked = _hasActiveApplication;
    // A fixed 3-item menu, always offered — each item individually
    // disabled (not hidden) when its own precondition doesn't hold, so the
    // set of actions is predictable rather than shifting around based on
    // state. Unlike Individual, Post Similar Requirement is never gated —
    // an organisation has no one-live-at-a-time limit.
    final menuActions = <_MenuAction>[
      _MenuAction(
        label: locked ? 'Edit the Requirement (Locked)' : 'Edit the Requirement',
        enabled: !locked,
        onSelected: onEdit,
      ),
      _MenuAction(label: 'Post Similar Requirement', enabled: true, onSelected: onPostSimilar),
      _MenuAction(
        label: _canCancel ? 'Cancel the Requirement' : 'Cancel the Requirement (Unavailable)',
        enabled: _canCancel,
        destructive: true,
        onSelected: onCancel,
      ),
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
            children: [
              Expanded(
                child: Text(organisationJobDisplayId(requirement),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(_statusLabel,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w600, color: _statusColor)),
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
            Text('Applicants (${applications.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
            const SizedBox(height: AppSpacing.sm),
            if (applications.isEmpty)
              const Text('No applicants yet.', style: TextStyle(color: AppColors.textSecondary))
            else
              for (final application in applications) ...[
                _ApplicantTile(
                  application: application,
                  isDeciding: decidingApplicationId.contains(application.id),
                  // Only one applicant can be accepted at a time (JOB_016
                  // backstops this server-side) — while someone is
                  // accepted, no one else (including a previously-rejected
                  // or completed candidate) offers an Accept action until
                  // that acceptance is undone via Reject.
                  canAccept: !_hasAcceptedApplicant,
                  canReject: (application.status == JobApplicationStatus.applied && !_hasAcceptedApplicant) ||
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
                if (!canAccept && !canReject && !_isAccepted)
                  Text(
                    application.status[0].toUpperCase() + application.status.substring(1),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
