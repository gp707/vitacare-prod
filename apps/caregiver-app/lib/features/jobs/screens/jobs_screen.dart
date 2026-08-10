import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';

/// SPEC.md 12.3 "Jobs Dashboard" — list of active job postings, viewable at
/// any verification status (browsing motivates onboarding). Responding is
/// gated server-side (JOB_001) to available/assigned caregivers only; a
/// caregiver in any other status sees the server's rejection message when
/// they try, rather than the buttons being hidden entirely — SPEC.md 12
/// says "view jobs; respond only if available/assigned", not "hide jobs".
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  List<JobModel> _jobs = [];
  bool _loading = true;
  String? _errorMessage;
  final Set<String> _respondingJobId = {};

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

  Future<void> _respond(JobModel job, String response, {String? message}) async {
    setState(() => _respondingJobId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).respondToJob(job.id, response, message: message);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _respondingJobId.remove(job.id));
    }
  }

  Future<void> _askForMoreDetails(JobModel job) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ask for More Details'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'What would you like to know?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (message == null || message.isEmpty || !mounted) return;
    await _respond(job, JobResponseType.moreDetails, message: message);
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
                        isResponding: _respondingJobId.contains(job.id),
                        onAccept: () => _respond(job, JobResponseType.accepted),
                        onReject: () => _respond(job, JobResponseType.rejected),
                        onAskForMoreDetails: () => _askForMoreDetails(job),
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
  final bool isResponding;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onAskForMoreDetails;

  const _JobCard({
    required this.job,
    required this.isResponding,
    required this.onAccept,
    required this.onReject,
    required this.onAskForMoreDetails,
  });

  @override
  Widget build(BuildContext context) {
    final salary = _salaryRangeFor(job.workType);
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
            WorkType.displayNames[job.workType] ?? job.workType,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (salary != null)
            Text('₹${salary.min} – ₹${salary.max}', style: const TextStyle(color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            children: [
              _Tag(City.displayNames[job.city] ?? job.city),
              _Tag(ServiceMode.displayNames[job.dutyTimings] ?? job.dutyTimings),
              _Tag(Language.displayNames[job.language] ?? job.language),
              _Tag(job.genderNeeded[0].toUpperCase() + job.genderNeeded.substring(1)),
              _Tag(Religion.displayNames[job.religion] ?? job.religion),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(job.description),
          const SizedBox(height: AppSpacing.md),
          if (isResponding)
            const Center(child: VitaLoadingIndicator())
          else if (job.myResponse != null)
            Text(
              'You responded: ${_responseLabel(job.myResponse!)}',
              style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(onPressed: onAccept, child: const Text('Accept')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextButton(onPressed: onAskForMoreDetails, child: const Text('More Info')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _responseLabel(String response) {
    switch (response) {
      case JobResponseType.accepted:
        return 'Accepted';
      case JobResponseType.rejected:
        return 'Rejected';
      case JobResponseType.moreDetails:
        return 'Asked for more details';
      default:
        return response;
    }
  }

  ({int min, int max})? _salaryRangeFor(String workType) {
    switch (workType) {
      case WorkType.companionCare:
        return SalaryRanges.companionCare;
      case WorkType.bedsideCare:
        return SalaryRanges.bedsideCare;
      case WorkType.criticalCare:
        return SalaryRanges.criticalCare;
      default:
        return null;
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
