import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../widgets/special_skills_char_limit_note.dart';

/// The "exclusive" org posting form — this is the whole form. No About
/// Patient section, no city/area/duty_type (every requirement inherits the
/// org's own registered location); no frequency_of_care/salary_amount
/// (admin-set on approval). See "NurseNow" in CLAUDE.md.
///
/// [cloneFrom], when supplied, pre-fills every org-owned field from a past
/// requirement (e.g. one that was just cancelled and the org wants to
/// repost) — same "Post Similar Requirement" convenience Individual's own
/// PostRequirementScreen offers. Always creates a brand-new requirement
/// with its own id and its own pending_review admin review.
class PostOrganisationRequirementScreen extends ConsumerStatefulWidget {
  final OrganisationRequirementModel? cloneFrom;

  const PostOrganisationRequirementScreen({super.key, this.cloneFrom});

  @override
  ConsumerState<PostOrganisationRequirementScreen> createState() => _PostOrganisationRequirementScreenState();
}

class _PostOrganisationRequirementScreenState extends ConsumerState<PostOrganisationRequirementScreen> {
  String? _typeOfNurse;
  final _typeOfNurseOtherController = TextEditingController();
  bool _accommodationProvided = false;
  bool _foodProvided = false;
  final _specialSkillsController = TextEditingController();
  final _numberOfVacanciesController = TextEditingController(text: '1');
  String? _preferredGender;
  String? _durationType;

  bool _saving = false;
  String? _error;
  bool _showValidationErrors = false;

  final _typeOfNurseKey = GlobalKey();
  final _typeOfNurseOtherKey = GlobalKey();
  final _numberOfVacanciesKey = GlobalKey();
  final _durationTypeKey = GlobalKey();
  final _specialSkillsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final source = widget.cloneFrom;
    if (source != null) {
      _typeOfNurse = source.typeOfNurse;
      _typeOfNurseOtherController.text = source.typeOfNurseOther ?? '';
      _accommodationProvided = source.accommodationProvided;
      _foodProvided = source.foodProvided;
      _specialSkillsController.text = source.specialSkills ?? '';
      _numberOfVacanciesController.text = source.numberOfVacancies.toString();
      _preferredGender = source.preferredGender;
      _durationType = source.durationType;
    }
  }

  bool get _isTypeOfNurseValid => _typeOfNurse != null;
  bool get _isTypeOfNurseOtherValid =>
      _typeOfNurse != TypeOfNurse.others || _typeOfNurseOtherController.text.trim().isNotEmpty;
  bool get _isNumberOfVacanciesValid {
    final value = int.tryParse(_numberOfVacanciesController.text.trim());
    return value != null && value > 0 && value < 50;
  }

  bool get _isDurationTypeValid => _durationType != null;

  /// Optional field, so an empty value is always valid — only invalid once
  /// typed/pasted past Validation.specialSkillsMaxLength, since the field
  /// itself has no hard Flutter `maxLength` (see SpecialSkillsCharLimitNote).
  bool get _isSpecialSkillsValid =>
      _specialSkillsController.text.length <= Validation.specialSkillsMaxLength;

  bool get _canSubmit =>
      !_saving &&
      _isTypeOfNurseValid &&
      _isTypeOfNurseOtherValid &&
      _isNumberOfVacanciesValid &&
      _isDurationTypeValid &&
      _isSpecialSkillsValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one seen when Submit scrolls/focuses to it.
  List<GlobalKey> get _mandatoryFieldKeysInOrder => [
        _typeOfNurseKey,
        if (_typeOfNurse == TypeOfNurse.others) _typeOfNurseOtherKey,
        _numberOfVacanciesKey,
        _durationTypeKey,
        if (!_isSpecialSkillsValid) _specialSkillsKey,
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
      await ref.read(organisationRepositoryProvider).createRequirement(
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
      appBar: AppBar(title: const VitaAppBarTitle('Post a Requirement'), actions: const [WhatsAppHelpButton()]),
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
              key: _specialSkillsKey,
              controller: _specialSkillsController,
              maxLines: 6,
              // Deliberately no `maxLength` here — it would silently
              // truncate a long paste (and can't show an over-limit count
              // at all). The org can keep typing/pasting past
              // Validation.specialSkillsMaxLength and see exactly how far
              // over in SpecialSkillsCharLimitNote below; the field's own
              // border/errorText turns red immediately once they do.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.star_outline),
                labelText: 'Job description/Special Skills (optional)',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                errorText: !_isSpecialSkillsValid
                    ? 'Please enter less than ${Validation.specialSkillsMaxLength} characters'
                    : null,
              ),
            ),
            SpecialSkillsCharLimitNote(currentLength: _specialSkillsController.text.length),
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
                  : const Icon(Icons.send, size: 18),
              label: const Text('Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }
}
