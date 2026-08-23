import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// The "exclusive" org posting form — this is the whole form. No About
/// Patient section, no city/area/duty_type (every requirement inherits the
/// org's own registered location); no frequency_of_care/salary_amount
/// (admin-set on approval). See "NurseNow" in CLAUDE.md.
class PostOrganisationRequirementScreen extends ConsumerStatefulWidget {
  const PostOrganisationRequirementScreen({super.key});

  @override
  ConsumerState<PostOrganisationRequirementScreen> createState() => _PostOrganisationRequirementScreenState();
}

class _PostOrganisationRequirementScreenState extends ConsumerState<PostOrganisationRequirementScreen> {
  String? _typeOfNurse;
  bool _accommodationProvided = false;
  bool _foodProvided = false;
  final _specialSkillsController = TextEditingController();

  bool _saving = false;
  String? _error;
  bool _showValidationErrors = false;

  final _typeOfNurseKey = GlobalKey();

  bool get _isTypeOfNurseValid => _typeOfNurse != null;
  bool get _canSubmit => !_saving && _isTypeOfNurseValid;

  @override
  void dispose() {
    _specialSkillsController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmitPressed() async {
    if (_saving) return;
    if (!_canSubmit) {
      setState(() => _showValidationErrors = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _typeOfNurseKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      });
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(organisationRepositoryProvider).createRequirement(
            typeOfNurse: _typeOfNurse!,
            accommodationProvided: _accommodationProvided,
            foodProvided: _foodProvided,
            specialSkills: _specialSkillsController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a Requirement'), actions: const [WhatsAppHelpButton()]),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: const Text(
                "An admin reviews every new requirement and sets the frequency of care, salary, "
                "and (for daily requirements) the preferred start date before it goes live and "
                "caregivers can see it. City/area are taken from your organisation's registered location.",
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              key: _typeOfNurseKey,
              isExpanded: true,
              initialValue: _typeOfNurse,
              decoration: InputDecoration(
                labelText: 'Type of Nurse/Caregiver (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isTypeOfNurseValid ? 'Please select a type' : null,
              ),
              items: TypeOfNurse.all
                  .map((t) => DropdownMenuItem(value: t, child: Text(TypeOfNurse.displayNames[t] ?? t)))
                  .toList(),
              onChanged: (value) => setState(() => _typeOfNurse = value),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Accommodation provided?'),
              value: _accommodationProvided,
              onChanged: (value) => setState(() => _accommodationProvided = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Food provided?'),
              value: _foodProvided,
              onChanged: (value) => setState(() => _foodProvided = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _specialSkillsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Special skills required (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _saving ? null : _handleSubmitPressed,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }
}
