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

  /// Doubles as "Approve" (from pending_review, sets frequency/salary/
  /// schedule for the first time) and "Edit" (from active/closed —
  /// admin can revisit/correct those same admin-set fields later; every
  /// other field stays org-owned, unchanged from `requirement`) — same
  /// dialog, same endpoint, only the label changes with current status.
  Future<void> _editRequirement(AdminOrganisationRequirement requirement) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditRequirementDialog(
        requirement: requirement,
        onSubmit: (frequency, salary, scheduleType, startDate, endDate, specificDays) async {
          await ref.read(adminOrganisationRequirementsRepositoryProvider).approve(
                requirement.id,
                typeOfNurse: requirement.typeOfNurse,
                frequencyOfCare: frequency,
                salaryAmount: salary,
                scheduleType: scheduleType,
                startDate: startDate,
                endDate: endDate,
                specificDays: specificDays,
                accommodationProvided: requirement.accommodationProvided,
                foodProvided: requirement.foodProvided,
                specialSkills: requirement.specialSkills,
              );
          await _load();
        },
      ),
    );
  }

  /// Row tap opens the full detail read-only; its own Edit button hands
  /// off to _editRequirement.
  Future<void> _viewDetail(AdminOrganisationRequirement requirement) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _RequirementReadOnlyDialog(
        requirement: requirement,
        onEdit: () {
          Navigator.of(dialogContext).pop();
          _editRequirement(requirement);
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
                        onTap: () => _viewDetail(requirement),
                        onEdit: () => _editRequirement(requirement),
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
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onReject;
  final VoidCallback onViewApplicants;

  const _RequirementRow({
    required this.requirement,
    required this.onTap,
    required this.onEdit,
    required this.onReject,
    required this.onViewApplicants,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Container(
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
                  Text('Requirement #${requirement.requirementNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  TextButton(
                    onPressed: onEdit,
                    child: Text(requirement.status == JobStatus.pendingReview ? 'Approve' : 'Edit'),
                  ),
                  if (onReject != null) TextButton(onPressed: onReject, child: const Text('Reject')),
                ],
              ),
            ],
          ),
        ),
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

/// Doubles as "Approve" (from pending_review) and "Edit" (from
/// active/closed, to revisit/correct these same admin-set fields later) —
/// see AdminOrganisationRequirementsScreen._editRequirement. Scheduling is
/// exactly one of two modes (see ScheduleType) — deliberately
/// organisation-only, unlike AdminJobsScreen's single Preferred Start Date.
class _EditRequirementDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final Future<void> Function(
    String frequency,
    int salary,
    String scheduleType,
    String? startDate,
    String? endDate,
    List<int>? specificDays,
  ) onSubmit;

  const _EditRequirementDialog({required this.requirement, required this.onSubmit});

  @override
  State<_EditRequirementDialog> createState() => _EditRequirementDialogState();
}

class _EditRequirementDialogState extends State<_EditRequirementDialog> {
  String? _frequency;
  late final _salaryController =
      TextEditingController(text: widget.requirement.salaryAmount?.toString() ?? '');
  String? _scheduleType;
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<int> _specificDays = {};
  bool _submitting = false;

  bool get _isApproval => widget.requirement.status == JobStatus.pendingReview;

  @override
  void initState() {
    super.initState();
    _frequency = widget.requirement.frequencyOfCare;
    _scheduleType = widget.requirement.scheduleType;
    final startDate = widget.requirement.startDate;
    final endDate = widget.requirement.endDate;
    if (startDate != null) _startDate = DateTime.tryParse(startDate);
    if (endDate != null) _endDate = DateTime.tryParse(endDate);
    if (widget.requirement.specificDays != null) _specificDays.addAll(widget.requirement.specificDays!);
  }

  @override
  void dispose() {
    _salaryController.dispose();
    super.dispose();
  }

  bool get _isDateRange => _scheduleType == ScheduleType.dateRange;
  bool get _isSpecificDays => _scheduleType == ScheduleType.specificDays;

  bool get _scheduleValid {
    if (_isDateRange) return _startDate != null && _endDate != null && !_endDate!.isBefore(_startDate!);
    if (_isSpecificDays) return _specificDays.isNotEmpty;
    return false;
  }

  bool get _canSubmit =>
      !_submitting && _frequency != null && int.tryParse(_salaryController.text.trim()) != null && _scheduleValid;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await widget.onSubmit(
      _frequency!,
      int.parse(_salaryController.text.trim()),
      _scheduleType!,
      _isDateRange ? _formatDate(_startDate!) : null,
      _isDateRange ? _formatDate(_endDate!) : null,
      _isSpecificDays ? (_specificDays.toList()..sort()) : null,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isApproval
            ? 'Approve requirement #${widget.requirement.requirementNumber}'
            : 'Edit requirement #${widget.requirement.requirementNumber}',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: AppSpacing.md),
              const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: ScheduleType.dateRange, label: Text('Date Range')),
                  ButtonSegment(value: ScheduleType.specificDays, label: Text('Specific Days')),
                ],
                selected: {if (_scheduleType != null) _scheduleType!},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) =>
                    setState(() => _scheduleType = selection.isEmpty ? null : selection.first),
              ),
              if (_isDateRange) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(_startDate == null ? 'Start date: not set' : 'Start date: ${_formatDate(_startDate!)}'),
                    ),
                    TextButton(onPressed: () => _pickDate(isStart: true), child: const Text('Pick date')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(_endDate == null ? 'End date: not set' : 'End date: ${_formatDate(_endDate!)}'),
                    ),
                    TextButton(onPressed: () => _pickDate(isStart: false), child: const Text('Pick date')),
                  ],
                ),
                if (_startDate != null && _endDate != null && _endDate!.isBefore(_startDate!))
                  const Text('End date must be on or after the start date', style: TextStyle(color: AppColors.error)),
              ],
              if (_isSpecificDays) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('Select the days of the month needed', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final day in List.generate(31, (i) => i + 1))
                      FilterChip(
                        label: Text('$day'),
                        selected: _specificDays.contains(day),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _specificDays.add(day);
                          } else {
                            _specificDays.remove(day);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
              : Text(_isApproval ? 'Approve' : 'Save Changes'),
        ),
      ],
    );
  }
}

class _ApplicantsDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final List<OrganisationRequirementApplicationModel> applications;
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

  void _viewProfile(OrganisationRequirementApplicationModel application) {
    Navigator.of(context).pushNamed('/caregiver-detail', arguments: application.profileId);
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
                          else ...[
                            TextButton(
                              onPressed: () => _viewProfile(application),
                              child: const Text('Profile'),
                            ),
                            if (application.status == JobApplicationStatus.applied) ...[
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

/// Read-only detail view opened by tapping a requirement row — every field
/// as plain text, with an Edit button handing off to _EditRequirementDialog.
class _RequirementReadOnlyDialog extends StatelessWidget {
  final AdminOrganisationRequirement requirement;
  final VoidCallback onEdit;

  const _RequirementReadOnlyDialog({required this.requirement, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Requirement #${requirement.requirementNumber}'),
          const SizedBox(width: AppSpacing.sm),
          _StatusBadge(status: requirement.status),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('Organisation', requirement.organisationName ?? '—'),
              _DetailRow(
                'Type',
                OrganisationType.displayNames[requirement.organisationType] ?? requirement.organisationType ?? '—',
              ),
              _DetailRow(
                'Location',
                [
                  if (requirement.city != null) City.displayNames[requirement.city] ?? requirement.city!,
                  if (requirement.area != null && requirement.area!.isNotEmpty) requirement.area!,
                ].join(', '),
              ),
              const Divider(height: AppSpacing.lg),
              _DetailRow('Type of Nurse', TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse),
              _DetailRow(
                'Frequency of Care',
                requirement.frequencyOfCare != null
                    ? FrequencyOfCare.displayNames[requirement.frequencyOfCare] ?? requirement.frequencyOfCare!
                    : 'Not set (admin sets on approval)',
              ),
              _DetailRow(
                'Salary',
                requirement.salaryAmount != null
                    ? '₹${requirement.salaryAmount}/${requirement.frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}'
                    : 'Not set (admin sets on approval)',
              ),
              _DetailRow(
                'Schedule',
                switch (requirement.scheduleType) {
                  ScheduleType.dateRange => '${requirement.startDate} – ${requirement.endDate}',
                  ScheduleType.specificDays => 'Days: ${requirement.specificDays?.join(', ')}',
                  _ => 'Not set (admin sets on approval)',
                },
              ),
              _DetailRow('Accommodation', requirement.accommodationProvided ? 'Provided' : 'Not provided'),
              _DetailRow('Food', requirement.foodProvided ? 'Provided' : 'Not provided'),
              if (requirement.specialSkills != null && requirement.specialSkills!.isNotEmpty)
                _DetailRow('Special Skills', requirement.specialSkills!),
              if (requirement.rejectionReason != null) _DetailRow('Rejection Reason', requirement.rejectionReason!),
              const Divider(height: AppSpacing.lg),
              _DetailRow('Posted', requirement.postedAt.split('T').first),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ElevatedButton(onPressed: onEdit, child: const Text('Edit')),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
