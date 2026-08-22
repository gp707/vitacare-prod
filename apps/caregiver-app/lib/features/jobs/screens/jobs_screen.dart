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

/// Unified list of active postings — admin/individual jobs AND organisation
/// (hospital/rehab/clinic) requirements shown together, sorted by post
/// date. Organisation requirements previously lived on their own separate
/// "Openings" tab; merged into one Jobs section on explicit request so a
/// caregiver only has to check one place. Applying is gated server-side
/// (JOB_001 for jobs, the same eligibility rule for requirements) to
/// available/assigned caregivers only; a caregiver in any other status sees
/// the server's rejection message when they try, rather than the buttons
/// being hidden entirely.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  List<JobModel> _jobs = [];
  List<OrganisationRequirementModel> _requirements = [];
  bool _loading = true;
  String? _errorMessage;
  final Set<String> _applyingId = {};

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
      final requirements = await ref.read(organisationOpeningsRepositoryProvider).listActive();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _requirements = requirements;
        });
      }
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

  Future<void> _applyToJob(JobModel job, String status) async {
    setState(() => _applyingId.add(job.id));
    try {
      await ref.read(jobsRepositoryProvider).applyToJob(job.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _applyingId.remove(job.id));
    }
  }

  Future<void> _applyToRequirement(OrganisationRequirementModel requirement, String status) async {
    setState(() => _applyingId.add(requirement.id));
    try {
      await ref.read(organisationOpeningsRepositoryProvider).apply(requirement.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _applyingId.remove(requirement.id));
    }
  }

  /// Withdraws a still-`applied` (not yet accepted) application — reuses
  /// the exact same apply endpoint with status 'rejected' that the
  /// pre-apply "Reject" button already calls (a caregiver-initiated
  /// withdrawal and a caregiver declining outright are the same server
  /// action: `decided_by` stays null either way, which is what tells the
  /// patient/family's own view "the caregiver did this", not them). Once
  /// this lands, the patient can no longer accept this caregiver for the
  /// job (JOB_007 backstops it server-side even if the UI somehow let
  /// them try), and the caregiver's phone number drops out of the
  /// patient's view of this application.
  Future<void> _withdrawJob(JobModel job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this job?'),
        content: const Text(
          "This withdraws your application. The patient/employer won't be able to accept you for this job "
          "anymore, and your contact details will no longer be shown to them.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close Job'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _applyToJob(job, JobApplicationStatus.rejected);
  }

  /// Same as [_withdrawJob], for an organisation requirement.
  Future<void> _withdrawRequirement(OrganisationRequirementModel requirement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this requirement?'),
        content: const Text(
          "This withdraws your application. The organisation won't be able to accept you for this "
          "requirement anymore, and your contact details will no longer be shown to them.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close Requirement'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _applyToRequirement(requirement, JobApplicationStatus.rejected);
  }

  List<_Listing> _mergedListings() {
    final listings = <_Listing>[
      ..._jobs.map(_JobListing.new),
      ..._requirements.map(_RequirementListing.new),
    ];
    listings.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return listings;
  }

  @override
  Widget build(BuildContext context) {
    final listings = _mergedListings();
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
                    if (listings.isEmpty && _errorMessage == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                        child: Text(
                          'No jobs posted right now. Pull down to refresh.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    for (final listing in listings) ...[
                      if (listing is _JobListing)
                        _JobCard(
                          job: listing.job,
                          isApplying: _applyingId.contains(listing.job.id),
                          onApply: () => _applyToJob(listing.job, JobApplicationStatus.applied),
                          onReject: () => _applyToJob(listing.job, JobApplicationStatus.rejected),
                          onWithdraw: () => _withdrawJob(listing.job),
                        )
                      else if (listing is _RequirementListing)
                        _RequirementCard(
                          requirement: listing.requirement,
                          isApplying: _applyingId.contains(listing.requirement.id),
                          onApply: () => _applyToRequirement(listing.requirement, JobApplicationStatus.applied),
                          onReject: () => _applyToRequirement(listing.requirement, JobApplicationStatus.rejected),
                          onWithdraw: () => _withdrawRequirement(listing.requirement),
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

/// Common shape the merged list sorts by — a job and an organisation
/// requirement have nothing else in common worth abstracting over (see
/// _JobCard/_RequirementCard below, which stay entirely separate widgets).
abstract class _Listing {
  DateTime get postedAt;
}

class _JobListing extends _Listing {
  final JobModel job;
  _JobListing(this.job);
  @override
  DateTime get postedAt => DateTime.parse(job.postedAt);
}

class _RequirementListing extends _Listing {
  final OrganisationRequirementModel requirement;
  _RequirementListing(this.requirement);
  @override
  DateTime get postedAt => DateTime.parse(requirement.postedAt);
}

class _JobCard extends StatelessWidget {
  final JobModel job;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onReject;
  final VoidCallback onWithdraw;

  const _JobCard({
    required this.job,
    required this.isApplying,
    required this.onApply,
    required this.onReject,
    required this.onWithdraw,
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
          else if (job.myApplication != null) ...[
            _ApplicationTimeline(job.myApplication!),
            // A caregiver can withdraw anytime while the patient/employer
            // still hasn't decided — once accepted, closing happens from
            // MyJobs instead (see my_assignment_screen.dart), and once
            // already rejected/completed there's nothing left to close.
            if (job.myApplication!.status == JobApplicationStatus.applied) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: onWithdraw, child: const Text('Close Job')),
              ),
            ],
          ] else
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

class _RequirementCard extends StatelessWidget {
  final OrganisationRequirementModel requirement;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onReject;
  final VoidCallback onWithdraw;

  const _RequirementCard({
    required this.requirement,
    required this.isApplying,
    required this.onApply,
    required this.onReject,
    required this.onWithdraw,
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
          Text(organisationJobDisplayId(requirement),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
          const SizedBox(height: AppSpacing.xs),
          _Tag(
            requirement.organisationType != null
                ? OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!
                : 'Organisation',
          ),
          const SizedBox(height: 2),
          Text(
            requirement.organisationName ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (requirement.organisationType != null || requirement.city != null)
            Text(
              [
                if (requirement.organisationType != null)
                  OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType!,
                if (requirement.city != null) City.displayNames[requirement.city] ?? requirement.city!,
                if (requirement.area != null && requirement.area!.isNotEmpty) requirement.area!,
              ].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          if (requirement.salaryAmount != null || organisationScheduleLabel(requirement) != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (requirement.salaryAmount != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Text(
                        '₹${requirement.salaryAmount}/${salaryUnit(requirement.frequencyOfCare)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.success),
                      ),
                    ),
                  ),
                if (requirement.salaryAmount != null && organisationScheduleLabel(requirement) != null)
                  const SizedBox(width: AppSpacing.xs),
                if (organisationScheduleLabel(requirement) != null)
                  Expanded(child: BlinkingStartDateBadge(label: organisationScheduleLabel(requirement)!)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _Tag(TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse),
              _Tag(requirement.accommodationProvided ? 'Accommodation provided' : 'No accommodation'),
              _Tag(requirement.foodProvided ? 'Food provided' : 'No food'),
            ],
          ),
          if (requirement.specialSkills != null && requirement.specialSkills!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(requirement.specialSkills!),
          ],
          const SizedBox(height: AppSpacing.md),
          if (isApplying)
            const Center(child: VitaLoadingIndicator())
          else if (requirement.myApplication != null) ...[
            _ApplicationTimeline(requirement.myApplication!),
            if (requirement.myApplication!.status == JobApplicationStatus.applied) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: onWithdraw, child: const Text('Close Requirement')),
              ),
            ],
          ] else
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: onApply, child: const Text('Apply'))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('Reject'))),
              ],
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Shows what actually happened to this application and when, instead of a
/// single bare status word — in particular this is what tells "you
/// declined it" (self) apart from "the employer declined you" (admin
/// rejected a still-applied application, or undid a prior acceptance —
/// both read the same to the caregiver: the employer said no). Shared by
/// both _JobCard and _RequirementCard — MyApplicationModel is the same
/// shape either way.
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
      if (application.declineReason != null && application.declineReason!.isNotEmpty) {
        lines.add('Reason: ${application.declineReason!}');
      }
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
