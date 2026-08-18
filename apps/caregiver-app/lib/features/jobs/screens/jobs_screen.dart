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
import 'job_preferences_screen.dart';

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

  Future<void> _openJobPreferences() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const JobPreferencesScreen()),
    );
    if (saved == true) await _load();
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
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Job Search Preferences',
            onPressed: _openJobPreferences,
          ),
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
          JobDetailCard(job: job),
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (job.myApplication != null)
            _ApplicationTimeline(job.myApplication!)
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
}

/// Shows what actually happened to this application and when, instead of a
/// single bare status word — in particular this is what tells "you
/// declined it" (self) apart from "the employer declined you" (admin
/// rejected a still-applied application, or undid a prior acceptance —
/// both read the same to the caregiver: the employer said no).
class _ApplicationTimeline extends StatelessWidget {
  final MyApplicationModel application;

  const _ApplicationTimeline(this.application);

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    if (application.appliedAt != null) {
      lines.add('Applied: ${formatDateTime(DateTime.parse(application.appliedAt!).toLocal())}');
    }
    if (application.acceptedAt != null) {
      lines.add('Accepted: ${formatDateTime(DateTime.parse(application.acceptedAt!).toLocal())}');
    }
    if (application.status == JobApplicationStatus.rejected && application.rejectedAt != null) {
      final label = application.decidedByAdmin ? 'Declined by employer' : 'Declined';
      lines.add('$label: ${formatDateTime(DateTime.parse(application.rejectedAt!).toLocal())}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Text(line, style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
      ],
    );
  }
}
