import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';

/// List of active job postings, viewable at any verification status
/// (browsing motivates onboarding). Applying is gated server-side
/// (JOB_001) to available/assigned caregivers only; a caregiver in any
/// other status sees the server's rejection message when they try, rather
/// than the buttons being hidden entirely.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  List<JobModel> _jobs = [];
  bool _loading = true;
  String? _errorMessage;
  final Set<String> _applyingJobId = {};

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
      if (mounted) setState(() => _jobs = jobs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply(JobModel job, String status) async {
    setState(() => _applyingJobId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).applyToJob(job.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _applyingJobId.remove(job.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
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
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 1),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (_errorMessage != null)
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                    if (_jobs.isEmpty && _errorMessage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          'No jobs posted right now. Pull down to refresh.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final job in _jobs) ...[
                      _JobCard(
                        job: job,
                        isApplying: _applyingJobId.contains(job.id),
                        onApply: () => _apply(job, JobApplicationStatus.applied),
                        onReject: () => _apply(job, JobApplicationStatus.rejected),
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

class _JobCard extends StatelessWidget {
  final JobModel job;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onReject;

  const _JobCard({
    required this.job,
    required this.isApplying,
    required this.onApply,
    required this.onReject,
  });

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
          Text(
            '${DutyType.displayNames[job.dutyType] ?? job.dutyType} in '
            '${City.displayNames[job.city] ?? job.city}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            children: [
              if (job.area != null && job.area!.isNotEmpty) _Tag(job.area!),
              _Tag(Language.displayNames[job.language] ?? job.language),
              if (job.preferredGender != null)
                _Tag(job.preferredGender![0].toUpperCase() + job.preferredGender!.substring(1)),
              if (job.preferredReligion != null)
                _Tag(Religion.displayNames[job.preferredReligion] ?? job.preferredReligion!),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(job.description),
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (job.myApplicationStatus != null)
            Text(
              _statusLabel(job.myApplicationStatus!),
              style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(onPressed: onApply, child: const Text('Apply')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case JobApplicationStatus.applied:
        return 'You applied';
      case JobApplicationStatus.accepted:
        return 'You were accepted';
      case JobApplicationStatus.rejected:
        return 'You declined';
      default:
        return status;
    }
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
