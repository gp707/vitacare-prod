import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import 'post_requirement_screen.dart';

/// Individual home screen — an account has at most one live requirement at
/// a time (pending_review or active both count as live), so this just
/// shows that one requirement (or a "post one" CTA if there isn't one) plus
/// its applicants once it's active, rather than a scrollable list.
class MyRequirementScreen extends ConsumerStatefulWidget {
  const MyRequirementScreen({super.key});

  @override
  ConsumerState<MyRequirementScreen> createState() => _MyRequirementScreenState();
}

class _MyRequirementScreenState extends ConsumerState<MyRequirementScreen> {
  bool _loading = true;
  String? _error;
  JobModel? _requirement;
  List<JobApplicationModel> _applications = [];
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
      final requirements = await ref.read(individualRepositoryProvider).listMyRequirements();
      // Most recent live/decided requirement first — durable history, but
      // there's realistically at most one live one at a time.
      final current = requirements.isEmpty ? null : requirements.first;
      List<JobApplicationModel> applications = [];
      if (current != null && current.status == JobStatus.active) {
        applications = await ref.read(individualRepositoryProvider).listApplications(current.id);
      }
      if (!mounted) return;
      setState(() {
        _requirement = current;
        _applications = applications;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String applicationId, String status) async {
    final requirement = _requirement;
    if (requirement == null) return;
    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(individualRepositoryProvider).decideApplication(requirement.id, applicationId, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId.remove(applicationId));
    }
  }

  Future<void> _postRequirement() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PostRequirementScreen()),
    );
    if (posted == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final isJobPostingBlocked = session is SessionAuthenticated && session.isJobPostingBlocked;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NurseNow'),
        actions: [
          TextButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              ref.read(sessionProvider.notifier).logout().then((_) {
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              });
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
                    if (_requirement == null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          "You don't have a requirement posted yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton(
                        onPressed: isJobPostingBlocked ? null : _postRequirement,
                        child: const Text('Post a Requirement'),
                      ),
                      if (isJobPostingBlocked) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          "Posting is currently blocked. Contact the office for details.",
                          style: TextStyle(color: AppColors.error),
                        ),
                      ],
                    ] else
                      _RequirementCard(
                        requirement: _requirement!,
                        applications: _applications,
                        decidingApplicationId: _decidingApplicationId,
                        onDecide: _decide,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RequirementCard extends StatelessWidget {
  final JobModel requirement;
  final List<JobApplicationModel> applications;
  final Set<String> decidingApplicationId;
  final void Function(String applicationId, String status) onDecide;

  const _RequirementCard({
    required this.requirement,
    required this.applications,
    required this.decidingApplicationId,
    required this.onDecide,
  });

  String get _statusLabel {
    switch (requirement.status) {
      case JobStatus.pendingReview:
        return 'Pending admin review';
      case JobStatus.active:
        return 'Live — visible to caregivers';
      case JobStatus.closed:
        return requirement.rejectionReason != null ? 'Rejected' : 'Closed';
      default:
        return requirement.status;
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
          Text('Job #${requirement.jobNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.xs),
          Text(_statusLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (requirement.status == JobStatus.closed && requirement.rejectionReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Reason: ${requirement.rejectionReason}', style: const TextStyle(color: AppColors.error)),
          ],
          if (requirement.status == JobStatus.active) ...[
            const SizedBox(height: AppSpacing.sm),
            if (requirement.salaryAmount != null)
              Text(
                '₹${requirement.salaryAmount}/${requirement.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text('${DutyType.displayNames[requirement.dutyType] ?? requirement.dutyType} in ${City.displayNames[requirement.city] ?? requirement.city}'),
          if (requirement.status == JobStatus.active) ...[
            const Divider(height: AppSpacing.lg),
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
  final JobApplicationModel application;
  final bool isDeciding;
  final void Function(String status) onDecide;

  const _ApplicantTile({required this.application, required this.isDeciding, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(application.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(application.phone, style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (isDeciding)
            const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
          else if (application.status == JobApplicationStatus.applied) ...[
            TextButton(onPressed: () => onDecide(JobApplicationStatus.accepted), child: const Text('Accept')),
            TextButton(onPressed: () => onDecide(JobApplicationStatus.rejected), child: const Text('Reject')),
          ] else
            Text(_capitalize(application.status)),
        ],
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
