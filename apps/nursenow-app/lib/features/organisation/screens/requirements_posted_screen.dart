import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../caregiver_profile/screens/caregiver_profile_view_screen.dart';
import 'post_organisation_requirement_screen.dart';

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

  Future<void> _decide(String requirementId, String applicationId, String status) async {
    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(organisationRepositoryProvider).decideApplication(requirementId, applicationId, status);
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isJobPostingBlocked = session is SessionAuthenticated && session.isJobPostingBlocked;

    return Scaffold(
      appBar: AppBar(title: const Text('Requirements Posted')),
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
                          onDecide: (applicationId, status) => _decide(requirement.id, applicationId, status),
                          onViewProfile: (applicationId) => _viewProfile(requirement.id, applicationId),
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

class _RequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final List<OrganisationRequirementApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId, String status) onDecide;
  final void Function(String applicationId) onViewProfile;

  const _RequirementCard({
    required this.requirement,
    required this.applications,
    required this.decidingApplicationId,
    required this.onDecide,
    required this.onViewProfile,
  });

  bool get _hasAcceptedApplicant => applications.any((a) => a.status == JobApplicationStatus.accepted);

  String get _statusLabel {
    switch (requirement.status) {
      case JobStatus.pendingReview:
        return 'Pending admin review';
      case JobStatus.active:
        return 'Live — visible to caregivers';
      case JobStatus.closed:
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
        return requirement.rejectionReason != null ? AppColors.error : AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Requirement #${requirement.requirementNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(_statusLabel, style: TextStyle(fontWeight: FontWeight.w600, color: _statusColor)),
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
          Wrap(
            children: [
              _Tag(TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse),
              if (requirement.startDate != null) _Tag('Start: ${requirement.startDate!}'),
              _Tag(requirement.accommodationProvided ? 'Accommodation provided' : 'No accommodation'),
              _Tag(requirement.foodProvided ? 'Food provided' : 'No food'),
            ],
          ),
          if (requirement.specialSkills != null && requirement.specialSkills!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(requirement.specialSkills!),
          ],
          if (requirement.status != JobStatus.pendingReview) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Text('Applicants (${applications.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            if (applications.isEmpty)
              const Text('No applicants yet.', style: TextStyle(color: AppColors.textSecondary))
            else
              for (final application in applications) ...[
                _ApplicantTile(
                  application: application,
                  isDeciding: decidingApplicationId.contains(application.id),
                  onDecide: (status) => onDecide(application.id, status),
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
  final void Function(String status) onDecide;
  final VoidCallback onViewProfile;

  const _ApplicantTile({
    required this.application,
    required this.isDeciding,
    required this.onDecide,
    required this.onViewProfile,
  });

  bool get _isAccepted => application.status == JobApplicationStatus.accepted;

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
                        Text(application.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
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
            Row(
              children: [
                OutlinedButton(onPressed: onViewProfile, child: const Text('View Profile')),
                const Spacer(),
                if (application.status == JobApplicationStatus.applied) ...[
                  TextButton(onPressed: () => onDecide(JobApplicationStatus.accepted), child: const Text('Accept')),
                  TextButton(onPressed: () => onDecide(JobApplicationStatus.rejected), child: const Text('Reject')),
                ] else
                  Text(
                    _isAccepted ? 'Accepted' : (application.status[0].toUpperCase() + application.status.substring(1)),
                    style: TextStyle(
                      color: _isAccepted ? AppColors.success : AppColors.textSecondary,
                      fontWeight: _isAccepted ? FontWeight.bold : FontWeight.normal,
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
