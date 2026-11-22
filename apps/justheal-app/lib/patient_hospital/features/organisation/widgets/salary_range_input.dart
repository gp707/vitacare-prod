import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';

/// Checks a typed salary range. Both boxes empty is fine when [required] is false (the range is
/// optional when posting); otherwise both must be whole rupee amounts 1–1,000,000 with the
/// maximum not below the minimum. Returns the message to show, or null when it is valid.
String? salaryRangeError(String minText, String maxText, {bool required = false}) {
  final minEmpty = minText.trim().isEmpty;
  final maxEmpty = maxText.trim().isEmpty;
  if (minEmpty && maxEmpty) return required ? 'Enter the lowest and highest salary' : null;
  if (minEmpty || maxEmpty) return 'Enter both the lowest and the highest salary';
  final min = int.tryParse(minText.trim());
  final max = int.tryParse(maxText.trim());
  if (min == null || max == null || min < 1 || max < 1 || min > 1000000 || max > 1000000) {
    return 'Enter whole rupee amounts';
  }
  if (max < min) return 'The highest salary cannot be below the lowest';
  return null;
}

/// Lowest salary, highest salary and Per day / Per month — shared by the posting form (optional)
/// and the "edit salary range" sheet. The caller owns the two controllers and the unit.
class SalaryRangeInput extends StatelessWidget {
  final TextEditingController minController;
  final TextEditingController maxController;
  final String unit; // 'daily' or 'monthly'
  final ValueChanged<String> onUnitChanged;
  final VoidCallback onChanged;
  final String? errorText;
  final bool enabled;

  const SalaryRangeInput({
    super.key,
    required this.minController,
    required this.maxController,
    required this.unit,
    required this.onUnitChanged,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final perUnit = unit == 'daily' ? 'day' : 'month';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          key: const Key('salary-range-unit'),
          segments: const [
            ButtonSegment(value: 'daily', label: Text('Per day')),
            ButtonSegment(value: 'monthly', label: Text('Per month')),
          ],
          selected: {unit},
          showSelectedIcon: false,
              style: ButtonStyle(
                // The chosen option is green (not the default grey) so it is obvious which one is active.
                backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? AppColors.success : null),
                foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? Colors.white : null),
              ),
          onSelectionChanged: enabled ? (selection) => onUnitChanged(selection.first) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('salary-range-min'),
                controller: minController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                maxLength: 7,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: 'Lowest (₹ per $perUnit)',
                  prefixText: '₹ ',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorText: errorText == null ? null : '',
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                key: const Key('salary-range-max'),
                controller: maxController,
                enabled: enabled,
                keyboardType: TextInputType.number,
                maxLength: 7,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: 'Highest (₹ per $perUnit)',
                  prefixText: '₹ ',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorText: errorText == null ? null : '',
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(errorText!, key: const Key('salary-range-error'), style: const TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }
}

/// A bottom sheet to set or change a requirement's salary range, kept clear of the keyboard.
/// [onSave] performs the save; an [ApiException] it throws is shown inline and the sheet stays
/// open. Returns true only when the range was saved.
Future<bool> showSalaryRangeSheet(
  BuildContext context, {
  int? initialMin,
  int? initialMax,
  String? initialUnit,
  required Future<void> Function(int min, int max, String unit) onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _SalaryRangeSheet(
      initialMin: initialMin,
      initialMax: initialMax,
      initialUnit: initialUnit ?? 'monthly',
      onSave: onSave,
    ),
  );
  return saved ?? false;
}

class _SalaryRangeSheet extends StatefulWidget {
  final int? initialMin;
  final int? initialMax;
  final String initialUnit;
  final Future<void> Function(int min, int max, String unit) onSave;

  const _SalaryRangeSheet({this.initialMin, this.initialMax, required this.initialUnit, required this.onSave});

  @override
  State<_SalaryRangeSheet> createState() => _SalaryRangeSheetState();
}

class _SalaryRangeSheetState extends State<_SalaryRangeSheet> {
  late final TextEditingController _min = TextEditingController(text: widget.initialMin?.toString() ?? '');
  late final TextEditingController _max = TextEditingController(text: widget.initialMax?.toString() ?? '');
  late String _unit = widget.initialUnit;
  bool _submitted = false;
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  String? get _error => salaryRangeError(_min.text, _max.text, required: true);

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_error != null) return;
    setState(() {
      _saving = true;
      _serverError = null;
    });
    try {
      await widget.onSave(int.parse(_min.text.trim()), int.parse(_max.text.trim()), _unit);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Salary range', style: TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text('Caregivers see this range on your requirement. You can change it any time.'),
              const SizedBox(height: AppSpacing.md),
              SalaryRangeInput(
                minController: _min,
                maxController: _max,
                unit: _unit,
                enabled: !_saving,
                onUnitChanged: (u) => setState(() => _unit = u),
                onChanged: () => setState(() {}),
                errorText: _submitted ? _error : null,
              ),
              if (_serverError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_serverError!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      key: const Key('salary-range-save'),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save'),
                    ),
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
