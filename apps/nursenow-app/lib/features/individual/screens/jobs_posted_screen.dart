import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/nursenow_bottom_nav.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
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

  Future<void> _decide(String jobId, String applicationId, String status) async {
    setState(() => _decidingApplicationId.add(applicationId));
    try {
      await ref.read(individualRepositoryProvider).decideApplication(jobId, applicationId, status);
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
    final hasLiveRequirement = _requirements.any(_isLive);

    return Scaffold(
      appBar: AppBar(title: const Text('Jobs Posted')),
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
                    else
                      for (final requirement in _requirements) ...[
                        _RequirementCard(
                          requirement: requirement,
                          applications: _applicationsByJobId[requirement.id] ?? const [],
                          decidingApplicationId: _decidingApplicationId,
                          onDecide: (applicationId, status) => _decide(requirement.id, applicationId, status),
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
    final careReceiver = requirement.careReceiver;
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
              Text('Job #${requirement.jobNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          Text(
            '${DutyType.displayNames[requirement.dutyType] ?? requirement.dutyType} in '
            '${City.displayNames[requirement.city] ?? requirement.city}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.md),
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
                _Tag(Mobility.displayNames[careReceiver.mobility] ?? careReceiver.mobility),
                _Tag(Communication.displayNames[careReceiver.communication] ?? careReceiver.communication),
                _Tag(FeedingType.displayNames[careReceiver.feedingType] ?? careReceiver.feedingType),
                for (final m in careReceiver.medicalAssistance) _Tag(MedicalAssistance.displayNames[m] ?? m),
                for (final t in careReceiver.toiletAssistance)
                  _Tag('Toilet: ${ToiletAssistance.displayNames[t] ?? t}'),
                if (careReceiver.hasMedicalCondition)
                  for (final c in careReceiver.medicalConditions) _Tag(MedicalCondition.displayNames[c] ?? c),
                if (careReceiver.requiresVitalMonitoring)
                  for (final v in careReceiver.vitalMonitoringTypes)
                    _Tag('Monitor: ${VitalMonitoringType.displayNames[v] ?? v}'),
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
          const _SectionLabel('About Nurse/Caregiver Requirement'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            children: [
              _Tag(DutyType.displayNames[requirement.dutyType] ?? requirement.dutyType),
              if (requirement.frequencyOfCare != null)
                _Tag(FrequencyOfCare.displayNames[requirement.frequencyOfCare!] ?? requirement.frequencyOfCare!),
              if (requirement.area != null && requirement.area!.isNotEmpty) _Tag(requirement.area!),
              if (requirement.startDate != null) _Tag('Start: ${requirement.startDate!}'),
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
      child: Row(
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
          if (isDeciding)
            const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
          else if (application.status == JobApplicationStatus.applied) ...[
            TextButton(onPressed: () => onDecide(JobApplicationStatus.accepted), child: const Text('Accept')),
            TextButton(onPressed: () => onDecide(JobApplicationStatus.rejected), child: const Text('Reject')),
          ] else
            Text(
              _isAccepted ? 'Accepted' : _capitalize(application.status),
              style: TextStyle(
                color: _isAccepted ? AppColors.success : AppColors.textSecondary,
                fontWeight: _isAccepted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }
}
