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

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Purely informational urgency message — never blocks applying, even once
/// the 3-day window has passed.
String _urgencyLabel(int daysLeft) {
  if (daysLeft <= 0) return 'Application window closed';
  if (daysLeft == 1) return '1 day left to apply';
  return '$daysLeft days left to apply';
}

Color _urgencyColor(int daysLeft) {
  if (daysLeft <= 0) return AppColors.error;
  if (daysLeft == 1) return AppColors.warning;
  return AppColors.success;
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Job #${job.jobNumber}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  _urgencyLabel(job.daysLeftToApply),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _urgencyColor(job.daysLeftToApply),
                  ),
                ),
              ),
            ],
          ),
          if (job.salaryMonthly != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                border: Border.all(color: AppColors.success),
              ),
              child: Text(
                '₹${job.salaryMonthly}/month',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${DutyType.displayNames[job.dutyType] ?? job.dutyType} in '
            '${City.displayNames[job.city] ?? job.city}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'Posted: ${_formatDate(DateTime.parse(job.postedAt))}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (job.careReceiver != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            const _SectionLabel('About Patient'),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              children: [
                _Tag('${job.careReceiver!.age} yrs'),
                _Tag(_capitalize(job.careReceiver!.gender)),
                _Tag('${job.careReceiver!.weightKg} kg'),
                _Tag(Mobility.displayNames[job.careReceiver!.mobility] ?? job.careReceiver!.mobility),
                _Tag(Communication.displayNames[job.careReceiver!.communication] ??
                    job.careReceiver!.communication),
                _Tag(FeedingType.displayNames[job.careReceiver!.feedingType] ??
                    job.careReceiver!.feedingType),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const _SectionLabel('About Patient Condition'),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              children: [
                for (final m in job.careReceiver!.medicalAssistance)
                  _Tag(MedicalAssistance.displayNames[m] ?? m),
                _Tag('Toilet: ${ToiletAssistance.displayNames[job.careReceiver!.toiletAssistance] ?? job.careReceiver!.toiletAssistance}'),
                if (job.careReceiver!.hasMedicalCondition)
                  for (final c in job.careReceiver!.medicalConditions)
                    _Tag(MedicalCondition.displayNames[c] ?? c),
                if (job.careReceiver!.requiresVitalMonitoring)
                  for (final v in job.careReceiver!.vitalMonitoringTypes)
                    _Tag('Monitor: ${VitalMonitoringType.displayNames[v] ?? v}'),
              ],
            ),
            if (job.careReceiver!.medicalInfo != null && job.careReceiver!.medicalInfo!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                job.careReceiver!.medicalInfo!,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          const _SectionLabel('About Nurse/Caregiver Requirement'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            children: [
              _Tag(DutyType.displayNames[job.dutyType] ?? job.dutyType),
              if (job.area != null && job.area!.isNotEmpty) _Tag(job.area!),
              for (final lang in job.languages) _Tag(Language.displayNames[lang] ?? lang),
              if (job.preferredGender != null) _Tag(_capitalize(job.preferredGender!)),
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
