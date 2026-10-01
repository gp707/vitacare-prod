import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/duty_requirements/duty_requirements_repository.dart';

/// Shows what the patient/family must arrange for the nurse under a given
/// shift (bedding/meals/supplies, no cooking or household chores, etc.) —
/// opened from the "Patient Provides" field on a job card. Admin-editable —
/// GET /duty-requirements, fetched fresh on every open (not cached), same
/// convention as ScopeOfWorkButton/RateCardButton. A wholly separate
/// admin-editable content set from Scope of Work (which describes
/// caregiving TASKS by care tier, not what the family must ARRANGE by
/// shift) — see admin-web's own "Duty Requirements" screen.
class DutyRequirementsDialog extends StatefulWidget {
  final String dutyType;
  final DutyRequirementsRepository repository;

  const DutyRequirementsDialog({super.key, required this.dutyType, required this.repository});

  @override
  State<DutyRequirementsDialog> createState() => DutyRequirementsDialogState();
}

class DutyRequirementsDialogState extends State<DutyRequirementsDialog> {
  DutyRequirementsModel? _dutyRequirements;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dutyRequirements = await widget.repository.get();
      if (mounted) setState(() => _dutyRequirements = dutyRequirements);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load duty requirements. Please try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(DutyType.displayNames[widget.dutyType] ?? widget.dutyType),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: VitaLoadingIndicator()),
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppColors.error))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final bullet in _dutyRequirements!.bulletsFor(widget.dutyType))
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  ',
                                    style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                                Expanded(
                                    child: Text(bullet,
                                        style: const TextStyle(
                                            color: AppColors.success, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
