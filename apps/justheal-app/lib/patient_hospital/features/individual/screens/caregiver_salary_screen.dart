import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/text_zoom_button.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../widgets/call_tap.dart';
import '../widgets/salary_actions.dart';
import '../widgets/salary_due_banner.dart';

/// One caregiver's salary and leave: what was agreed, the next salary due, the
/// days marked as leave and any pause. Opened from the caregiver's tile on the
/// requirement screen.
///
/// For the caregiver currently on the job everything can be changed here (edit the
/// agreement, mark or cancel leave days, pause or resume salary). For one who is no
/// longer on the job (rejected, or closed duty) the same details stay as a read-only
/// record of what was agreed.
class CaregiverSalaryScreen extends ConsumerStatefulWidget {
  final JobModel requirement;
  final String applicationId;

  const CaregiverSalaryScreen({super.key, required this.requirement, required this.applicationId});

  @override
  ConsumerState<CaregiverSalaryScreen> createState() => _CaregiverSalaryScreenState();
}

class _CaregiverSalaryScreenState extends ConsumerState<CaregiverSalaryScreen> {
  JobApplicationModel? _application;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final applications = await ref.read(individualRepositoryProvider).listApplications(widget.requirement.id);
      final match = applications.where((a) => a.id == widget.applicationId).firstOrNull;
      if (mounted) {
        setState(() {
          _application = match;
          _error = match == null ? 'This caregiver could not be found.' : null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Runs an action from [salary_actions.dart], then refreshes this page.
  Future<void> _act(Future<bool> Function(JobApplicationModel application) action) async {
    final application = _application;
    if (application == null) return;
    final changed = await action(application);
    if (changed) await _load();
  }

  String get _jobId => widget.requirement.id;
  bool get _isAccepted => _application?.status == JobApplicationStatus.accepted;

  String _unitWord(JobApplicationModel a) {
    final unit = a.agreedSalaryUnit ?? (widget.requirement.frequencyOfCare == FrequencyOfCare.daily ? 'daily' : 'monthly');
    return unit == 'daily' ? 'day' : 'month';
  }

  @override
  Widget build(BuildContext context) {
    final application = _application;
    return Scaffold(
      appBar: VitaAppBar(
        title: application?.fullName ?? 'Salary & leaves',
        actions: const [TextZoomButton(), WhatsAppHelpButton()],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : application == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(_error ?? 'Not found.', style: const TextStyle(color: AppColors.error)),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        _header(application),
                        const SizedBox(height: AppSpacing.md),
                        _agreementCard(application),
                        if (_isAccepted && application.agreedSalary != null && application.agreedStartDate != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _nextSalary(application),
                        ],
                        if (application.agreedSalary != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _leaveCard(application),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── Header: who, and whether they are still on the job ───────────────────

  Widget _header(JobApplicationModel application) {
    final (label, color) = switch (application.status) {
      JobApplicationStatus.accepted => ('Accepted', AppColors.success),
      JobApplicationStatus.rejected => ('No longer on this job (rejected)', AppColors.error),
      JobApplicationStatus.completed => ('Closed duty', AppColors.textSecondary),
      _ => (application.status, AppColors.textSecondary),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(application.fullName, style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, key: const Key('salary-status'), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.xs),
          CallTap(
            phone: application.phone,
            name: application.fullName,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call, size: 14, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(application.phone,
                      style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ),
          if (!_isAccepted) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'This caregiver is no longer on this job. What was agreed with them is kept here as a record.',
              key: Key('salary-past-note'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
            ),
          ],
        ],
      ),
    );
  }

  // ── Agreement ────────────────────────────────────────────────────────────

  Widget _agreementCard(JobApplicationModel application) {
    final salary = application.agreedSalary;
    final startDate = application.agreedStartDate;
    final has = salary != null && startDate != null;
    return _Card(
      title: 'Agreed salary',
      icon: Icons.handshake_outlined,
      children: [
        if (has) ...[
          Text(
            '₹${formatRupees(salary)} per ${_unitWord(application)}',
            key: const Key('agreed-salary'),
            style: const TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold, color: AppColors.success),
          ),
          Text('Starts ${formatLongDate(startDate)}', key: const Key('agreed-start')),
        ] else
          Text(
            _isAccepted ? 'No salary has been agreed yet.' : 'No salary was agreed with this caregiver.',
            key: const Key('no-agreement'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        if (_isAccepted) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: Key(has ? 'edit-agreement' : 'add-agreement'),
            onPressed: () => _act(
              (a) => openAgreementFlow(context, ref, jobId: _jobId, requirement: widget.requirement, application: a),
            ),
            icon: Icon(has ? Icons.edit_outlined : Icons.add, size: 18),
            label: Text(has ? 'Edit salary & date' : 'Add agreed salary & start date'),
          ),
        ],
      ],
    );
  }

  // ── Next salary due (only while they are on the job) ─────────────────────

  Widget _nextSalary(JobApplicationModel application) {
    final due = nextSalaryDue(
      salary: application.agreedSalary,
      unit: application.agreedSalaryUnit ??
          (widget.requirement.frequencyOfCare == FrequencyOfCare.daily ? 'daily' : 'monthly'),
      startDate: application.agreedStartDate,
      leaveDates: application.leaveDates,
      pauses: application.pauses,
    );
    if (due == null) return const SizedBox.shrink();
    return SalaryDueBanner(
      entries: [SalaryDueEntry(label: application.fullName, due: due)],
      caption: 'Pay the caregiver directly. JustHeal does not handle payments.',
      margin: EdgeInsets.zero,
    );
  }

  // ── Leave days and pause ─────────────────────────────────────────────────

  Widget _leaveCard(JobApplicationModel application) {
    final openPauses = application.pauses.where((p) => p.isOpen).toList();
    final isPaused = openPauses.isNotEmpty;
    final pastPauses = application.pauses.where((p) => !p.isOpen && p.to != p.from).toList();
    return _Card(
      title: 'Leave days',
      icon: Icons.event_busy_outlined,
      children: [
        if (isPaused)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Salary paused since ${formatLongDate(openPauses.first.from)}. Days until you resume count as leave.',
              key: const Key('paused-note'),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800),
            ),
          ),
        for (final pause in pastPauses)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Paused ${formatLongDate(pause.from)} to ${formatLongDate(pause.to!)}',
              style: TextStyle(color: Colors.deepOrange.shade800),
            ),
          ),
        if (application.leaveDates.isEmpty)
          const Text('No leave days marked.', key: Key('no-leave'), style: TextStyle(color: AppColors.textSecondary))
        else ...[
          Text(
            _isAccepted ? 'Marked as leave (tap x to cancel a day)' : 'Marked as leave',
            style: TextStyle(fontSize: AppTypography.small, color: Colors.deepOrange.shade800, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final date in application.leaveDates)
                InputChip(
                  key: Key('leave-chip-$date'),
                  label: Text(formatDayMonth(date), style: const TextStyle(fontSize: AppTypography.small)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.deepOrange.shade50,
                  side: BorderSide(color: Colors.deepOrange.shade400),
                  // Only the caregiver currently on the job can have a day cancelled.
                  deleteIcon: _isAccepted ? const Icon(Icons.close, size: 16) : null,
                  deleteButtonTooltipMessage: 'Cancel leave on ${formatDayMonth(date)}',
                  onDeleted: _isAccepted
                      ? () => _act((a) => cancelLeaveFlow(context, ref, jobId: _jobId, application: a, date: date))
                      : null,
                ),
            ],
          ),
        ],
        if (_isAccepted) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('mark-leave'),
                  onPressed: () => _act((a) => markLeaveFlow(context, ref, jobId: _jobId, application: a)),
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: const Text('Mark leave'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: isPaused
                    ? FilledButton.icon(
                        key: const Key('resume-salary'),
                        onPressed: () => _act((a) => resumeSalaryFlow(context, ref, jobId: _jobId, application: a)),
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: const Text('Resume'),
                      )
                    : OutlinedButton.icon(
                        key: const Key('pause-salary'),
                        onPressed: () => _act((a) => pauseSalaryFlow(context, ref, jobId: _jobId, application: a)),
                        icon: const Icon(Icons.pause_circle_outline, size: 18),
                        label: const Text('Pause salary'),
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A titled white card used for each section of the page.
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Card({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.xs),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.subtitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}
