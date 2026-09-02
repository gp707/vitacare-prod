import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/providers.dart';
import '../../../core/duty_requirements/duty_requirements_repository.dart';

/// A small ⓘ info button placed next to the "Hours Care Needed" dropdown on
/// nursenow-app's Individual Post/Edit Requirement forms — tapping it shows
/// what the patient/family must arrange for the nurse under whichever
/// shift is currently selected (bedding/meals/supplies, no cooking or
/// household chores, etc.). Disabled (greyed out, no tap target) until a
/// shift is actually selected, since the content depends entirely on which
/// one — there's no single answer to show beforehand.
///
/// Admin-editable — GET /duty-requirements, fetched fresh on every tap
/// (not cached), same convention as ScopeOfWorkButton/RateCardButton. This
/// is a wholly separate admin-editable content set from Scope of Work
/// (which describes caregiving TASKS by care tier, not what the family
/// must ARRANGE by shift) — see admin-web's own "Duty Requirements" screen.
class DutyRequirementsInfoButton extends ConsumerWidget {
  final String? dutyType;

  const DutyRequirementsInfoButton({super.key, required this.dutyType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = dutyType;
    return IconButton(
      icon: const Icon(Icons.info_outline),
      color: AppColors.primary,
      tooltip: selected == null
          ? 'Select Hours Care Needed to see what to arrange for the nurse'
          : 'What to arrange for the nurse',
      onPressed: selected == null
          ? null
          : () => showDialog(
                context: context,
                builder: (_) => DutyRequirementsDialog(
                  dutyType: selected,
                  repository: ref.read(dutyRequirementsRepositoryProvider),
                ),
              ),
    );
  }
}

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
      // Green background, white bullet text — the shift heading (title
      // below) stays black, since it was never given an explicit color
      // and so keeps rendering in the theme's default text color
      // regardless of the surface behind it.
      backgroundColor: AppColors.success,
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
                                const Text('•  ', style: TextStyle(color: Colors.white)),
                                Expanded(child: Text(bullet, style: const TextStyle(color: Colors.white))),
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
