import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../widgets/job_detail_card.dart';
import '../widgets/job_poster_contact_card.dart';

/// Every job the caregiver is currently accepted onto or has completed. A
/// caregiver can hold more than one accepted job at once, so this is a
/// list, not a single job — GET /caregiver/jobs only lists active jobs, and
/// an accepted job closes immediately, so without this screen an assigned
/// caregiver would have no way to see their own jobs' details again. The
/// "MyJobs" bottom-nav tab, reachable regardless of current verification
/// status, so it still shows past assignments even after the caregiver has
/// completed every job (durable history — completed jobs stay listed).
class MyAssignmentScreen extends ConsumerStatefulWidget {
  const MyAssignmentScreen({super.key});

  @override
  ConsumerState<MyAssignmentScreen> createState() => _MyAssignmentScreenState();
}

class _MyAssignmentScreenState extends ConsumerState<MyAssignmentScreen> {
  List<JobModel> _jobs = [];
  bool _loading = true;
  String? _errorMessage;
  String? _completingJobId;

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
      final jobs = await ref.read(jobsRepositoryProvider).getAssignedJobs();
      if (mounted) setState(() => _jobs = jobs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeJob(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark job as complete?'),
        content: Text(
          "This marks Job #${job.jobNumber} as finished. If you don't have any other accepted jobs, "
          "you'll be shown as available for new ones again.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _completingJobId = job.id);
    try {
      final stillAssigned = await ref.read(jobsRepositoryProvider).completeJob(job.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              stillAssigned
                  ? 'Job #${job.jobNumber} marked complete.'
                  : "Job #${job.jobNumber} marked complete. You're now available for new jobs.",
            ),
          ),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _completingJobId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyJobs'),
        actions: [
          const WhatsAppHelpButton(),
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
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 2),
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
                          "You don't have any accepted jobs yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final job in _jobs) ...[
                      _AssignedJobCard(
                        job: job,
                        completing: _completingJobId == job.id,
                        onMarkComplete: () => _completeJob(job),
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

class _AssignedJobCard extends StatelessWidget {
  final JobModel job;
  final bool completing;
  final VoidCallback onMarkComplete;

  const _AssignedJobCard({required this.job, required this.completing, required this.onMarkComplete});

  @override
  Widget build(BuildContext context) {
    final isCompleted = job.myApplication?.status == JobApplicationStatus.completed;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobDetailCard(job: job),
          const SizedBox(height: AppSpacing.md),
          if (isCompleted)
            const Text(
              'Completed',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
            )
          else ...[
            const Text(
              'You were accepted for this job',
              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: completing ? null : onMarkComplete,
                child: completing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Mark Complete'),
              ),
            ),
          ],
          if (job.jobPoster != null) ...[
            const SizedBox(height: AppSpacing.md),
            JobPosterContactCard(poster: job.jobPoster!),
          ],
        ],
      ),
    );
  }
}
