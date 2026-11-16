import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';

/// The popup shown right after the patient/family accepts a caregiver (and
/// again from "Add agreed salary & start date" on the accepted candidate while
/// it is still empty): two fields, the salary and start date they agreed on,
/// which are sent to the caregiver. "Fill later" closes it without saving.
///
/// [onSubmit] performs the save; an [ApiException] it throws is shown inline so
/// the dialog stays open and the patient can fix the value. Returns true only
/// when the agreement was saved.
Future<bool> showAgreementDialog(
  BuildContext context, {
  required String caregiverName,
  required String defaultUnit, // 'daily' or 'monthly' — preselected (the job's own frequency)
  required Future<void> Function(int salary, String salaryUnit, String startDate) onSubmit,
  int? initialSalary,
  String? initialSalaryUnit,
  String? initialStartDate,
}) async {
  // A bottom sheet, not a centred dialog: it sits above the on-screen keyboard and scrolls,
  // so the number keyboard never covers the salary field or the Save button.
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AgreementDialog(
      caregiverName: caregiverName,
      defaultUnit: defaultUnit,
      onSubmit: onSubmit,
      initialSalary: initialSalary,
      initialSalaryUnit: initialSalaryUnit,
      initialStartDate: initialStartDate,
    ),
  );
  return saved ?? false;
}

class _AgreementDialog extends StatefulWidget {
  final String caregiverName;
  final String defaultUnit;
  final Future<void> Function(int salary, String salaryUnit, String startDate) onSubmit;
  final int? initialSalary;
  final String? initialSalaryUnit;
  final String? initialStartDate;

  const _AgreementDialog({
    required this.caregiverName,
    required this.defaultUnit,
    required this.onSubmit,
    this.initialSalary,
    this.initialSalaryUnit,
    this.initialStartDate,
  });

  @override
  State<_AgreementDialog> createState() => _AgreementDialogState();
}

class _AgreementDialogState extends State<_AgreementDialog> {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  late final TextEditingController _salaryController;
  late String _unit; // 'daily' or 'monthly'
  DateTime? _startDate;
  bool _submitted = false; // flags empty fields only after the first tap on Save
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _salaryController = TextEditingController(text: widget.initialSalary?.toString() ?? '');
    _unit = widget.initialSalaryUnit ?? widget.defaultUnit;
    final initial = widget.initialStartDate;
    if (initial != null) _startDate = DateTime.tryParse(initial);
  }

  @override
  void dispose() {
    _salaryController.dispose();
    super.dispose();
  }

  int? get _salary {
    final value = int.tryParse(_salaryController.text.trim());
    return (value != null && value >= 1 && value <= 1000000) ? value : null;
  }

  String _display(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: (_startDate != null && !_startDate!.isBefore(today)) ? _startDate! : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final salary = _salary;
    final date = _startDate;
    if (salary == null || date == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(salary, _unit, _iso(date));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salaryInvalid = _submitted && _salary == null;
    final dateMissing = _submitted && _startDate == null;
    return Padding(
      // Lifts the whole sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      // Keeps the buttons clear of the phone's own navigation bar at the bottom.
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm salary and start date',
              style: TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Clarity avoids confusion and future issues. Please enter the salary and start date '
              'you agreed on; they will be sent to the caregiver.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Please understand these are care staff, not house maids. We hope they get respect and '
              'are treated the way you treat your own family members.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: AppSpacing.md),
            // The salary can be agreed per day or per month — the patient picks.
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Per day')),
                ButtonSegment(value: 'monthly', label: Text('Per month')),
              ],
              selected: {_unit},
              showSelectedIcon: false,
              onSelectionChanged: _saving ? null : (selection) => setState(() => _unit = selection.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _salaryController,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              maxLength: 7,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Agreed Salary (₹ per ${_unit == 'daily' ? 'day' : 'month'})',
                prefixText: '₹ ',
                counterText: '',
                border: const OutlineInputBorder(),
                errorText: salaryInvalid ? 'Enter the agreed salary in rupees' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: _saving ? null : _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Start date',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today, size: 18),
                  errorText: dateMissing ? 'Pick the start date' : null,
                ),
                child: Text(_startDate == null ? 'Select a date' : _display(_startDate!)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            // A Wrap so the buttons stack on a narrow screen or with large text.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Fill later'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save & send to caregiver'),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
