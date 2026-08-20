import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../data/admin_organisation_requirements_repository.dart';

/// Row/dialog widgets for an organisation requirement, extracted out of the
/// former standalone AdminOrganisationRequirementsScreen so AdminJobsScreen
/// can render organisation requirements merged into its single Jobs list.
/// Kept as a distinct set of widgets (not unified with _JobRow/_JobFormDialog
/// in admin_jobs_screen.dart) since organisation_requirements is a wholly
/// separate table/model from jobs (see "NurseNow" in CLAUDE.md) — only the
/// browse/list view is merged, not the underlying create/edit shapes.
class RequirementRow extends StatelessWidget {
  final AdminOrganisationRequirement requirement;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onReject;
  final VoidCallback onViewApplicants;

  const RequirementRow({
    super.key,
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
                  Text(requirementDisplayId(requirement), style: const TextStyle(fontWeight: FontWeight.bold)),
                  RequirementStatusBadge(status: requirement.status),
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

class RequirementStatusBadge extends StatelessWidget {
  final String status;

  const RequirementStatusBadge({super.key, required this.status});

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
/// active/closed, to revisit/correct these same admin-set fields later).
/// Scheduling is exactly one of two modes (see ScheduleType) — deliberately
/// organisation-only, unlike AdminJobsScreen's single Preferred Start Date.
class EditRequirementDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final Future<void> Function(
    String frequency,
    int salary,
    String scheduleType,
    String? startDate,
    String? endDate,
    String? scheduleRepeat,
    List<int>? specificDays,
  ) onSubmit;

  const EditRequirementDialog({super.key, required this.requirement, required this.onSubmit});

  @override
  State<EditRequirementDialog> createState() => _EditRequirementDialogState();
}

class _EditRequirementDialogState extends State<EditRequirementDialog> {
  String? _frequency;
  late final _salaryController =
      TextEditingController(text: widget.requirement.salaryAmount?.toString() ?? '');
  String? _scheduleType;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _scheduleRepeat;
  final Set<int> _specificDays = {};
  bool _submitting = false;

  bool get _isApproval => widget.requirement.status == JobStatus.pendingReview;

  @override
  void initState() {
    super.initState();
    _frequency = widget.requirement.frequencyOfCare;
    _scheduleType = widget.requirement.scheduleType;
    _scheduleRepeat = widget.requirement.scheduleRepeat;
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
  bool get _isWeekly => _scheduleRepeat == ScheduleRepeat.weekly;
  bool get _isMonthly => _scheduleRepeat == ScheduleRepeat.monthly;

  bool get _scheduleValid {
    if (_isDateRange) return _startDate != null && _endDate != null && !_endDate!.isBefore(_startDate!);
    if (_isSpecificDays) return _scheduleRepeat != null && _specificDays.isNotEmpty;
    return false;
  }

  bool get _canSubmit =>
      !_submitting && _frequency != null && int.tryParse(_salaryController.text.trim()) != null && _scheduleValid;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void _setScheduleRepeat(String repeat) {
    setState(() {
      _scheduleRepeat = repeat;
      _specificDays.clear();
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await widget.onSubmit(
      _frequency!,
      int.parse(_salaryController.text.trim()),
      _scheduleType!,
      _isDateRange ? _formatDate(_startDate!) : null,
      _isDateRange ? _formatDate(_endDate!) : null,
      _isSpecificDays ? _scheduleRepeat : null,
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
            ? 'Approve ${requirementDisplayId(widget.requirement)}'
            : 'Edit ${requirementDisplayId(widget.requirement)}',
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
                    if (_startDate != null) ...[
                      const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(_startDate == null ? 'Start date: not set' : 'Start date: ${_formatDate(_startDate!)}'),
                    ),
                    TextButton(onPressed: () => _pickDate(isStart: true), child: const Text('Pick date')),
                  ],
                ),
                Row(
                  children: [
                    if (_endDate != null) ...[
                      const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                    ],
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
                const Text('Repeat', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.xs),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: ScheduleRepeat.weekly, label: Text('Weekly')),
                    ButtonSegment(value: ScheduleRepeat.monthly, label: Text('Monthly')),
                  ],
                  selected: {if (_scheduleRepeat != null) _scheduleRepeat!},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (selection) =>
                      selection.isEmpty ? setState(() => _scheduleRepeat = null) : _setScheduleRepeat(selection.first),
                ),
                if (_isWeekly) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Select the days of the week needed (repeats every week)',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (var weekday = 1; weekday <= 7; weekday++)
                        FilterChip(
                          label: Text(ScheduleRepeat.weekdayAbbreviations[weekday]!),
                          selected: _specificDays.contains(weekday),
                          selectedColor: AppColors.success.withValues(alpha: 0.2),
                          checkmarkColor: AppColors.success,
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _specificDays.add(weekday);
                            } else {
                              _specificDays.remove(weekday);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                if (_isMonthly) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Select the days of the month needed (repeats every month)',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.xs),
                  _MonthCalendarPicker(
                    selectedDays: _specificDays,
                    onToggle: (day) => setState(() {
                      if (_specificDays.contains(day)) {
                        _specificDays.remove(day);
                      } else {
                        _specificDays.add(day);
                      }
                    }),
                  ),
                ],
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

/// A real month-grid calendar (weekday-aligned, current month) for picking
/// recurring days-of-month — only the tapped day NUMBER is captured (e.g.
/// 15), not the specific date, since the selection recurs every month
/// regardless of what weekday the 15th falls on in other months. Shown
/// purely for a familiar, visual way to pick numbers rather than scanning a
/// flat 1-31 list.
class _MonthCalendarPicker extends StatelessWidget {
  final Set<int> selectedDays;
  final ValueChanged<int> onToggle;

  const _MonthCalendarPicker({required this.selectedDays, required this.onToggle});

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leadingBlanks = DateTime(now.year, now.month, 1).weekday - 1; // Monday=1 -> 0 blanks

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_monthNames[now.month - 1]} ${now.year}',
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final label in const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'])
              Expanded(
                child: Center(
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.xs,
          crossAxisSpacing: AppSpacing.xs,
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (final day in List.generate(daysInMonth, (i) => i + 1))
              _CalendarDayCell(day: day, selected: selectedDays.contains(day), onTap: () => onToggle(day)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text('Selections recur every month, regardless of the day of the week.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final int day;
  final bool selected;
  final VoidCallback onTap;

  const _CalendarDayCell({required this.day, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.success.withValues(alpha: 0.2) : null,
          border: Border.all(color: selected ? AppColors.success : AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: selected
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Text('$day', style: const TextStyle(fontSize: 12)),
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(Icons.check_circle, color: AppColors.success, size: 12),
                  ),
                ],
              )
            : Text('$day', style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class RequirementApplicantsDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final List<OrganisationRequirementApplicationModel> applications;
  final Future<void> Function(String applicationId, String status) onDecide;

  const RequirementApplicantsDialog({
    super.key,
    required this.requirement,
    required this.applications,
    required this.onDecide,
  });

  @override
  State<RequirementApplicantsDialog> createState() => _RequirementApplicantsDialogState();
}

class _RequirementApplicantsDialogState extends State<RequirementApplicantsDialog> {
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
      title: Text('Applicants — ${requirementDisplayId(widget.requirement)}'),
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

/// Same wording as the shared organisationJobDisplayId() helper — kept as
/// a local copy since AdminOrganisationRequirement is admin-web's own
/// model (not the shared OrganisationRequirementModel that helper expects).
String requirementDisplayId(AdminOrganisationRequirement requirement) => 'ORG-JOB-${requirement.requirementNumber}';

/// Same wording as the shared organisationScheduleLabel() helper — kept as
/// a local copy since AdminOrganisationRequirement is admin-web's own
/// model (not the shared OrganisationRequirementModel that helper expects).
String scheduleSummary(AdminOrganisationRequirement requirement) {
  switch (requirement.scheduleType) {
    case ScheduleType.dateRange:
      return '${requirement.startDate} – ${requirement.endDate}';
    case ScheduleType.specificDays:
      final days = requirement.specificDays;
      if (days == null || days.isEmpty) return 'Not set (admin sets on approval)';
      if (requirement.scheduleRepeat == ScheduleRepeat.weekly) {
        final sorted = [...days]..sort();
        final names = sorted.map((d) => ScheduleRepeat.weekdayAbbreviations[d] ?? '$d').join(', ');
        return 'Every: $names';
      }
      return 'Days: ${days.join(', ')}';
    default:
      return 'Not set (admin sets on approval)';
  }
}

/// Read-only detail view opened by tapping a requirement row — every field
/// as plain text, with an Edit button handing off to EditRequirementDialog.
class RequirementReadOnlyDialog extends StatelessWidget {
  final AdminOrganisationRequirement requirement;
  final VoidCallback onEdit;

  const RequirementReadOnlyDialog({super.key, required this.requirement, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(requirementDisplayId(requirement)),
          const SizedBox(width: AppSpacing.sm),
          RequirementStatusBadge(status: requirement.status),
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
              _DetailRow('Schedule', scheduleSummary(requirement)),
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
