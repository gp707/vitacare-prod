import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

// Seconds are included (not just hours:minutes) so two actions taken within
// the same minute — e.g. two applicants deciding within seconds of each
// other — still display in a visibly distinguishable, correctly ordered
// sequence. The underlying DateTime already carries full precision from the
// backend (Postgres timestamptz); this only affects what's shown, not how
// anything is sorted (sorting already compares full DateTime/ISO values).
String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:'
    '${date.second.toString().padLeft(2, '0')}';

/// Applicants dialog for a single job, fetched by [jobId] — usable from
/// anywhere a job id is known (the Jobs list's own "Applicants" button, or
/// a cross-link from an audit log entry), not just when a JobModel is
/// already loaded in memory.
class JobDetailDialog extends ConsumerStatefulWidget {
  final String jobId;

  const JobDetailDialog({super.key, required this.jobId});

  @override
  ConsumerState<JobDetailDialog> createState() => _JobDetailDialogState();
}

class _JobDetailDialogState extends ConsumerState<JobDetailDialog> {
  JobModel? _job;
  List<JobApplicationModel>? _applications;
  String? _errorMessage;
  String? _decidingApplicationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (job, applications) =
          await ref.read(adminJobsRepositoryProvider).getDetail(widget.jobId);
      if (mounted) {
        setState(() {
          _job = job;
          _applications = applications;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _decide(JobApplicationModel application, String status) async {
    setState(() => _decidingApplicationId = application.id);
    try {
      await ref
          .read(adminJobsRepositoryProvider)
          .decideApplication(widget.jobId, application.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId = null);
    }
  }

  void _viewProfile(JobApplicationModel application) {
    Navigator.of(context)
        .pushNamed('/caregiver-detail', arguments: application.profileId);
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return AlertDialog(
      title: Text(
        job == null
            ? 'Job'
            : 'Applicants — ${jobDisplayId(job)} · '
                '${DutyType.displayNames[job.dutyType] ?? job.dutyType} in '
                '${City.displayNames[job.city] ?? job.city}',
      ),
      content: SizedBox(
        width: context.dialogWidth(480),
        child: _errorMessage != null
            ? Text(_errorMessage!,
                style: const TextStyle(color: AppColors.error))
            : _applications == null
                ? const Center(child: VitaLoadingIndicator())
                : _applications!.isEmpty
                    ? const Text('No applicants yet.',
                        style: TextStyle(color: AppColors.textSecondary))
                    : SizedBox(
                        height: 340,
                        child: ListView.separated(
                          itemCount: _applications!.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final application = _applications![index];
                            final isDeciding =
                                _decidingApplicationId == application.id;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  '${application.fullName} — ${application.status}'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(application.phone),
                                  const SizedBox(height: 2),
                                  _ApplicationTimeline(application),
                                ],
                              ),
                              trailing: isDeciding
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: VitaLoadingIndicator(size: 20),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: () =>
                                              _viewProfile(application),
                                          child: const Text('Profile'),
                                        ),
                                        if (application.status ==
                                            JobApplicationStatus.applied) ...[
                                          TextButton(
                                            onPressed: () => _decide(
                                                application,
                                                JobApplicationStatus.accepted),
                                            child: const Text('Accept'),
                                          ),
                                          TextButton(
                                            onPressed: () => _decide(
                                                application,
                                                JobApplicationStatus.rejected),
                                            style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.error),
                                            child: const Text('Reject'),
                                          ),
                                        ] else if (application.status ==
                                            JobApplicationStatus.accepted)
                                          TextButton(
                                            onPressed: () => _decide(
                                                application,
                                                JobApplicationStatus.rejected),
                                            style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.error),
                                            child: const Text('Reject'),
                                          ),
                                      ],
                                    ),
                            );
                          },
                        ),
                      ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }
}

/// Shows the real per-transition history (applied/accepted/declined, with
/// timestamps) instead of a bare status word, and — unlike the caregiver's
/// own view — names which admin made the accept/reject decision.
class _ApplicationTimeline extends StatelessWidget {
  final JobApplicationModel application;

  const _ApplicationTimeline(this.application);

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    if (application.appliedAt != null) {
      lines.add(
          'Applied: ${_formatDateTime(DateTime.parse(application.appliedAt!).toLocal())}');
    }
    if (application.acceptedAt != null) {
      lines.add(
        'Accepted: ${_formatDateTime(DateTime.parse(application.acceptedAt!).toLocal())}'
        '${application.decidedByName != null ? ' by ${application.decidedByName}' : ''}',
      );
    }
    if (application.status == JobApplicationStatus.rejected &&
        application.rejectedAt != null) {
      final decider = application.decidedByName;
      final label = decider != null ? 'Declined by $decider' : 'Declined';
      lines.add(
          '$label: ${_formatDateTime(DateTime.parse(application.rejectedAt!).toLocal())}');
      if (application.declineReason != null &&
          application.declineReason!.isNotEmpty) {
        lines.add('Reason: ${application.declineReason!}');
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Text(line,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
