import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// Edits the org-owned fields of the org's own requirement — every field
/// there is, since admin owns none of them (approval is a pure
/// approve/reject click, see OrganisationRequirementsService.
/// approveRequirement). Allowed regardless of the requirement's own status
/// (pending_review/active/closed) — only gated on there being no active
/// application (JOB_014), matching Individual's own EditRequirementScreen.
class EditOrganisationRequirementScreen extends ConsumerStatefulWidget {
  final OrganisationRequirementModel requirement;

  const EditOrganisationRequirementScreen({super.key, required this.requirement});

  @override
  ConsumerState<EditOrganisationRequirementScreen> createState() =>
      _EditOrganisationRequirementScreenState();
}

class _EditOrganisationRequirementScreenState extends ConsumerState<EditOrganisationRequirementScreen> {
  late String? _typeOfNurse;
  late final _typeOfNurseOtherController =
      TextEditingController(text: widget.requirement.typeOfNurseOther ?? '');
  late bool _accommodationProvided;
  late bool _foodProvided;
  late final _specialSkillsController =
      TextEditingController(text: widget.requirement.specialSkills ?? '');
  late final _numberOfVacanciesController =
      TextEditingController(text: widget.requirement.numberOfVacancies.toString());
  late String? _preferredGender;
  late String? _durationType;

  bool _saving = false;
  String? _error;
  bool _showValidationErrors = false;

  final _typeOfNurseKey = GlobalKey();
  final _typeOfNurseOtherKey = GlobalKey();
  final _numberOfVacanciesKey = GlobalKey();
  final _durationTypeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _typeOfNurse = widget.requirement.typeOfNurse;
    _accommodationProvided = widget.requirement.accommodationProvided;
    _foodProvided = widget.requirement.foodProvided;
    _preferredGender = widget.requirement.preferredGender;
    _durationType = widget.requirement.durationType;
  }

  bool get _isTypeOfNurseValid => _typeOfNurse != null;
  bool get _isTypeOfNurseOtherValid =>
      _typeOfNurse != TypeOfNurse.others || _typeOfNurseOtherController.text.trim().isNotEmpty;
  bool get _isNumberOfVacanciesValid {
    final value = int.tryParse(_numberOfVacanciesController.text.trim());
    return value != null && value > 0 && value < 50;
  }

  bool get _isDurationTypeValid => _durationType != null;

  bool get _canSubmit =>
      !_saving &&
      _isTypeOfNurseValid &&
      _isTypeOfNurseOtherValid &&
      _isNumberOfVacanciesValid &&
      _isDurationTypeValid;

  List<GlobalKey> get _mandatoryFieldKeysInOrder => [
        _typeOfNurseKey,
        if (_typeOfNurse == TypeOfNurse.others) _typeOfNurseOtherKey,
        _numberOfVacanciesKey,
        _durationTypeKey,
      ];

  @override
  void dispose() {
    _typeOfNurseOtherController.dispose();
    _specialSkillsController.dispose();
    _numberOfVacanciesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmitPressed() async {
    if (_saving) return;
    if (!_canSubmit) {
      setState(() => _showValidationErrors = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final key in _mandatoryFieldKeysInOrder) {
          final ctx = key.currentContext;
          if (ctx == null) continue;
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          break;
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
      await ref.read(organisationRepositoryProvider).editRequirement(
            widget.requirement.id,
            typeOfNurse: _typeOfNurse!,
            typeOfNurseOther:
                _typeOfNurse == TypeOfNurse.others ? _typeOfNurseOtherController.text.trim() : null,
            accommodationProvided: _accommodationProvided,
            foodProvided: _foodProvided,
            specialSkills: _specialSkillsController.text.trim(),
            numberOfVacancies: int.parse(_numberOfVacanciesController.text.trim()),
            preferredGender: _preferredGender,
            durationType: _durationType!,
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
      appBar: AppBar(title: const VitaAppBarTitle('Edit Requirement'), actions: const [WhatsAppHelpButton()]),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            DropdownButtonFormField<String>(
              key: _typeOfNurseKey,
              isExpanded: true,
              initialValue: _typeOfNurse,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.medical_services),
                labelText: 'Type of Nurse/Caregiver (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isTypeOfNurseValid ? 'Please select a type' : null,
              ),
              items: TypeOfNurse.all
                  .map((t) => DropdownMenuItem(value: t, child: Text(TypeOfNurse.displayNames[t] ?? t)))
                  .toList(),
              onChanged: (value) => setState(() => _typeOfNurse = value),
            ),
            if (_typeOfNurse == TypeOfNurse.others) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: _typeOfNurseOtherKey,
                controller: _typeOfNurseOtherController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Please specify (Mandatory)',
                  border: const OutlineInputBorder(),
                  errorText: _showValidationErrors && !_isTypeOfNurseOtherValid
                      ? 'Please specify the type of nurse/caregiver'
                      : null,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: _numberOfVacanciesKey,
              controller: _numberOfVacanciesController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.people),
                labelText: 'Number of Vacancies (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isNumberOfVacanciesValid
                    ? 'Enter a number between 1 and 49'
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: _durationTypeKey,
              isExpanded: true,
              initialValue: _durationType,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.hourglass_bottom),
                labelText: 'Duration (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isDurationTypeValid ? 'Please select a duration' : null,
              ),
              items: RequirementDuration.all
                  .map((d) => DropdownMenuItem(value: d, child: Text(RequirementDuration.displayNames[d] ?? d)))
                  .toList(),
              onChanged: (value) => setState(() => _durationType = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _preferredGender,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.people_outline),
                labelText: 'Preferred Caregiver Gender',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('No preference')),
                DropdownMenuItem(value: Gender.male, child: Text('Male')),
                DropdownMenuItem(value: Gender.female, child: Text('Female')),
              ],
              onChanged: (value) => setState(() => _preferredGender = value),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.home, color: AppColors.primaryDark),
              title: const Text('Accommodation provided?'),
              value: _accommodationProvided,
              onChanged: (value) => setState(() => _accommodationProvided = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.restaurant, color: AppColors.primaryDark),
              title: const Text('Food provided?'),
              value: _foodProvided,
              onChanged: (value) => setState(() => _foodProvided = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _specialSkillsController,
              maxLines: 3,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.star_outline),
                labelText: 'Special skills required (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: _saving ? null : _handleSubmitPressed,
              icon: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
