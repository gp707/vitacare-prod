import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// The "Duty Requirements" tab of the Settings hub — lets an admin edit the
/// 3 independent bullet lists (24Hrs Live-In / Day Shift / Night Shift)
/// shown to a patient/family (nursenow-app) via the "Hours Care Needed"
/// info button — which list that button shows is whichever shift is
/// currently selected on the form, never picked here. Unlike Scope of
/// Work's tiers, these 3 lists are NOT cumulative — each shift stands
/// alone. Same free-length-bullet-list editing pattern otherwise (bullets
/// can be added/removed, not just edited in place).
class DutyRequirementsSettingsSection extends ConsumerStatefulWidget {
  const DutyRequirementsSettingsSection({super.key});

  @override
  ConsumerState<DutyRequirementsSettingsSection> createState() =>
      _DutyRequirementsSettingsSectionState();
}

class _DutyRequirementsSettingsSectionState extends ConsumerState<DutyRequirementsSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  String? _updatedByName;
  String? _updatedAt;

  List<TextEditingController> _liveInControllers = [];
  List<TextEditingController> _dayDutyControllers = [];
  List<TextEditingController> _nightDutyControllers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [..._liveInControllers, ..._dayDutyControllers, ..._nightDutyControllers]) {
      c.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> _controllersFor(List<String> bullets) =>
      bullets.map((b) => TextEditingController(text: b)).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final withUpdater = await ref.read(dutyRequirementsRepositoryProvider).get();
      if (!mounted) return;
      final dutyRequirements = withUpdater.dutyRequirements;
      setState(() {
        _liveInControllers = _controllersFor(dutyRequirements.liveIn);
        _dayDutyControllers = _controllersFor(dutyRequirements.dayDuty);
        _nightDutyControllers = _controllersFor(dutyRequirements.nightDuty);
        _updatedByName = withUpdater.updatedByName;
        _updatedAt = withUpdater.updatedAt;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final dutyRequirements = DutyRequirementsModel(
        liveIn: _liveInControllers.map((c) => c.text.trim()).toList(),
        dayDuty: _dayDutyControllers.map((c) => c.text.trim()).toList(),
        nightDuty: _nightDutyControllers.map((c) => c.text.trim()).toList(),
      );
      await ref.read(dutyRequirementsRepositoryProvider).update(dutyRequirements);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duty requirements saved')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: VitaLoadingIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _buildForm(),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What the patient/family must arrange for the nurse, shown via the info button next '
          'to "Hours Care Needed" on a NurseNow individual\'s Post/Edit Requirement form. Each '
          'shift\'s list is independent — none of them stack with each other.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        _buildShiftSection(
          title: '24Hrs - Live In',
          controllers: _liveInControllers,
          onChanged: (updated) => setState(() => _liveInControllers = updated),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildShiftSection(
          title: '12Hrs Day Shift (8am to 8pm)',
          controllers: _dayDutyControllers,
          onChanged: (updated) => setState(() => _dayDutyControllers = updated),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildShiftSection(
          title: '12Hrs Night Shift (8pm to 8am)',
          controllers: _nightDutyControllers,
          onChanged: (updated) => setState(() => _nightDutyControllers = updated),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_updatedByName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Last updated by $_updatedByName${_updatedAt != null ? ' on $_updatedAt' : ''}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
            ),
          ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildShiftSection({
    required String title,
    required List<TextEditingController> controllers,
    required void Function(List<TextEditingController>) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < controllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controllers[i],
                      decoration: const InputDecoration(labelText: 'Bullet'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    tooltip: 'Remove bullet',
                    onPressed: () {
                      final updated = [...controllers];
                      updated.removeAt(i).dispose();
                      onChanged(updated);
                    },
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => onChanged([...controllers, TextEditingController()]),
            icon: const Icon(Icons.add),
            label: const Text('Add bullet'),
          ),
        ],
      ),
    );
  }
}
