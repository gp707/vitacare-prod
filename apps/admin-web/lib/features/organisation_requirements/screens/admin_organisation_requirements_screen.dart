import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/admin_organisation_requirements_repository.dart';

/// Admin never *creates* an organisation requirement (the org posts its
/// own) — this screen only approves/edits/rejects pending_review ones and
/// decides on applicants. A separate screen/data model from AdminJobsScreen
/// since organisation_requirements is a dedicated table (see "NurseNow" in
/// CLAUDE.md).
class AdminOrganisationRequirementsScreen extends ConsumerStatefulWidget {
  const AdminOrganisationRequirementsScreen({super.key});

  @override
  ConsumerState<AdminOrganisationRequirementsScreen> createState() => _AdminOrganisationRequirementsScreenState();
}

class _AdminOrganisationRequirementsScreenState extends ConsumerState<AdminOrganisationRequirementsScreen> {
  List<AdminOrganisationRequirement> _requirements = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final items = await ref.read(adminOrganisationRequirementsRepositoryProvider).list();
      if (mounted) setState(() => _requirements = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject(AdminOrganisationRequirement requirement) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reject requirement'),
          content: TextField(
            controller: controller,
            maxLength: 1000,
            maxLines: 4,
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(labelText: 'Reason (shown to the organisation)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: controller.text.trim().isEmpty ? null : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminOrganisationRequirementsRepositoryProvider).reject(requirement.id, controller.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _approve(AdminOrganisationRequirement requirement) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ApproveDialog(
        requirement: requirement,
        onSubmit: (frequency, salary, startDate) async {
          await ref.read(adminOrganisationRequirementsRepositoryProvider).approve(
                requirement.id,
                typeOfNurse: requirement.typeOfNurse,
                frequencyOfCare: frequency,
                salaryAmount: salary,
                startDate: startDate,
                accommodationProvided: requirement.accommodationProvided,
                foodProvided: requirement.foodProvided,
                specialSkills: requirement.specialSkills,
              );
          await _load();
        },
      ),
    );
  }

  Future<void> _viewApplicants(AdminOrganisationRequirement requirement) async {
    final (_, applications) = await ref.read(adminOrganisationRequirementsRepositoryProvider).getDetail(requirement.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ApplicantsDialog(
        requirement: requirement,
        applications: applications,
        onDecide: (applicationId, status) async {
          await ref
              .read(adminOrganisationRequirementsRepositoryProvider)
              .decideApplication(requirement.id, applicationId, status);
          await _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.rehabRequirements,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Organisation Requirements', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else if (_requirements.isEmpty)
                const Expanded(child: Center(child: Text('No organisation requirements posted yet.')))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _requirements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final requirement = _requirements[index];
                      return _RequirementRow(
                        requirement: requirement,
                        onApprove: requirement.status == JobStatus.pendingReview ? () => _approve(requirement) : null,
                        onReject: requirement.status == JobStatus.pendingReview ? () => _reject(requirement) : null,
                        onViewApplicants: () => _viewApplicants(requirement),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final AdminOrganisationRequirement requirement;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback onViewApplicants;

  const _RequirementRow({
    required this.requirement,
    required this.onApprove,
    required this.onReject,
    required this.onViewApplicants,
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
              Text('Requirement #${requirement.requirementNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
              _StatusBadge(status: requirement.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(requirement.organisationName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (requirement.rejectionReason != null)
            Text('Reason: ${requirement.rejectionReason}', style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              Text(TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse),
              if (requirement.salaryAmount != null)
                Text(
                  '· ₹${requirement.salaryAmount}/${requirement.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}',
                  style: const TextStyle(color: AppColors.success),
                ),
              Text('· ${requirement.accommodationProvided ? 'Accommodation' : 'No accommodation'}'),
              Text('· ${requirement.foodProvided ? 'Food' : 'No food'}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            children: [
              TextButton(onPressed: onViewApplicants, child: const Text('Applicants')),
              if (onApprove != null) TextButton(onPressed: onApprove, child: const Text('Approve')),
              if (onReject != null) TextButton(onPressed: onReject, child: const Text('Reject')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      JobStatus.pendingReview => Colors.orange,
      JobStatus.active => AppColors.success,
      _ => AppColors.textSecondary,
    };
    final label = switch (status) {
      JobStatus.pendingReview => 'Pending Review',
      JobStatus.active => 'Active',
      JobStatus.closed => 'Closed',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final Future<void> Function(String frequency, int salary, String? startDate) onSubmit;

  const _ApproveDialog({required this.requirement, required this.onSubmit});

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  String? _frequency;
  final _salaryController = TextEditingController();
  DateTime? _startDate;
  bool _submitting = false;

  @override
  void dispose() {
    _salaryController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _frequency != null &&
      int.tryParse(_salaryController.text.trim()) != null &&
      (_frequency != FrequencyOfCare.daily || _startDate != null);

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final startDateStr = _startDate == null
        ? null
        : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}';
    await widget.onSubmit(_frequency!, int.parse(_salaryController.text.trim()), startDateStr);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Approve requirement #${widget.requirement.requirementNumber}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequency of Care'),
              items: FrequencyOfCare.all
                  .map((f) => DropdownMenuItem(value: f, child: Text(FrequencyOfCare.displayNames[f] ?? f)))
                  .toList(),
              onChanged: (value) => setState(() => _frequency = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _salaryController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _frequency == FrequencyOfCare.daily ? 'Salary (₹/day)' : 'Salary (₹/month)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_frequency == FrequencyOfCare.daily) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(_startDate == null
                        ? 'Preferred start date: not set'
                        : 'Preferred start date: ${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? now,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                    child: const Text('Pick date'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
              : const Text('Approve'),
        ),
      ],
    );
  }
}

class _ApplicantsDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final List<JobApplicationModel> applications;
  final Future<void> Function(String applicationId, String status) onDecide;

  const _ApplicantsDialog({required this.requirement, required this.applications, required this.onDecide});

  @override
  State<_ApplicantsDialog> createState() => _ApplicantsDialogState();
}

class _ApplicantsDialogState extends State<_ApplicantsDialog> {
  String? _decidingId;

  Future<void> _decide(String applicationId, String status) async {
    setState(() => _decidingId = applicationId);
    await widget.onDecide(applicationId, status);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Applicants — Requirement #${widget.requirement.requirementNumber}'),
      content: SizedBox(
        width: 400,
        child: widget.applications.isEmpty
            ? const Text('No applicants yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final application in widget.applications)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(application.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(application.phone),
                              ],
                            ),
                          ),
                          if (_decidingId == application.id)
                            const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
                          else if (application.status == JobApplicationStatus.applied) ...[
                            TextButton(
                              onPressed: () => _decide(application.id, JobApplicationStatus.accepted),
                              child: const Text('Accept'),
                            ),
                            TextButton(
                              onPressed: () => _decide(application.id, JobApplicationStatus.rejected),
                              child: const Text('Reject'),
                            ),
                          ] else
                            Text(application.status),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
