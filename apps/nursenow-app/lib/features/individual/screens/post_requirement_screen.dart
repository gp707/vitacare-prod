import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/individual_repository.dart';

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Same About Patient / location / duty-type / language-preference fields
/// as admin's job-posting form — minus Frequency of Care and Salary, which
/// an admin sets later on approval. Creates a pending_review requirement.
///
/// Submit is always tappable (mirrors admin-web's AdminJobsScreen form): if
/// a mandatory field is missing, tapping it flags every missing mandatory
/// field red and scrolls/focuses straight to the first one instead of
/// submitting — rather than a single generic top-of-form error message.
class PostRequirementScreen extends ConsumerStatefulWidget {
  const PostRequirementScreen({super.key});

  @override
  ConsumerState<PostRequirementScreen> createState() => _PostRequirementScreenState();
}

class _PostRequirementScreenState extends ConsumerState<PostRequirementScreen> {
  final _ageController = TextEditingController();
  String? _gender;
  final _weightController = TextEditingController();
  String? _mobility;
  String? _communication;
  String? _feedingType;
  final List<String> _medicalAssistance = [];
  bool _hasMedicalCondition = false;
  final List<String> _medicalConditions = [];
  final _medicalConditionOtherController = TextEditingController();
  final List<String> _toiletAssistance = [];
  final _toiletAssistanceOtherController = TextEditingController();
  bool _requiresVitalMonitoring = false;
  final List<String> _vitalMonitoringTypes = [];

  String? _city;
  final _areaController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _dutyType;
  DateTime? _startDate;
  final List<String> _languages = [];
  String? _preferredGender;
  String? _preferredReligion;

  bool _saving = false;
  String? _error;

  // Only text-based mandatory fields need a FocusNode — that's what lets
  // Submit literally put the cursor in the first one that's missing.
  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _areaFocusNode = FocusNode();

  // One key per mandatory field, in the order they appear on the form, so
  // Submit can scroll to whichever one is first still-invalid.
  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _startDateKey = GlobalKey();
  final _languagesKey = GlobalKey();

  // Only turns true once Submit has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _areaController.dispose();
    _descriptionController.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _areaFocusNode.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());

  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid => _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isStartDateValid => _startDate != null;
  bool get _isLanguagesValid => _languages.isNotEmpty;

  bool get _canSubmit =>
      !_saving &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isCityValid &&
      _isAreaValid &&
      _isDutyTypeValid &&
      _isStartDateValid &&
      _isLanguagesValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one the patient/family sees when Submit scrolls them to it.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid, focusNode: _weightFocusNode),
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_startDateKey, _isStartDateValid),
        _MandatoryField(_languagesKey, _isLanguagesValid),
      ];

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  /// Submit is always tappable — this is what runs when it's pressed. With
  /// something missing, it flags every missing mandatory field red and
  /// jumps straight to the first one instead of submitting.
  Future<void> _handleSubmitPressed() async {
    if (_saving) return;
    if (!_canSubmit) {
      setState(() => _showValidationErrors = true);
      _MandatoryField? firstInvalid;
      for (final field in _mandatoryFieldsInOrder) {
        if (!field.isValid) {
          firstInvalid = field;
          break;
        }
      }
      if (firstInvalid != null) {
        final target = firstInvalid;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = target.key.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
          target.focusNode?.requestFocus();
        });
      }
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
      await ref.read(individualRepositoryProvider).createRequirement(
            careReceiver: CareReceiverInput(
              age: _age!,
              gender: _gender!,
              weightKg: _weightKg!,
              mobility: _mobility,
              communication: _communication,
              feedingType: _feedingType,
              medicalAssistance: _medicalAssistance.isEmpty ? null : _medicalAssistance,
              hasMedicalCondition: _hasMedicalCondition,
              medicalConditions: _hasMedicalCondition ? _medicalConditions : null,
              medicalConditionOther: _medicalConditionOtherController.text.trim(),
              toiletAssistance: _toiletAssistance.isEmpty ? null : _toiletAssistance,
              toiletAssistanceOther: _toiletAssistanceOtherController.text.trim(),
              requiresVitalMonitoring: _requiresVitalMonitoring,
              vitalMonitoringTypes: _requiresVitalMonitoring ? _vitalMonitoringTypes : null,
            ),
            city: _city!,
            area: _areaController.text.trim(),
            description: _descriptionController.text.trim(),
            dutyType: _dutyType!,
            startDate: '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            languages: _languages,
            preferredGender: _preferredGender,
            preferredReligion: _preferredReligion,
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
      appBar: AppBar(title: const Text('Post a Requirement')),
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
                "An admin reviews every new requirement and sets the frequency of care and salary before it goes live and caregivers can see it.",
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('About Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: _ageKey,
              controller: _ageController,
              focusNode: _ageFocusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Patient's Age (Mandatory)",
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isAgeValid ? 'Age is required (1-120)' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: _genderKey,
              isExpanded: true,
              initialValue: _gender,
              decoration: InputDecoration(
                labelText: "Patient's Gender (Mandatory)",
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isGenderValid ? 'Please select a gender' : null,
              ),
              items: Gender.all
                  .map((g) => DropdownMenuItem(value: g, child: Text(_capitalize(g))))
                  .toList(),
              onChanged: (value) => setState(() => _gender = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: _weightKey,
              controller: _weightController,
              focusNode: _weightFocusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Patient's Weight (kg) (Mandatory)",
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isWeightValid ? 'Weight is required (1-300 kg)' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _mobility,
              decoration: const InputDecoration(labelText: 'Mobility (optional)', border: OutlineInputBorder()),
              items: Mobility.all
                  .map((m) => DropdownMenuItem(value: m, child: Text(Mobility.displayNames[m] ?? m)))
                  .toList(),
              onChanged: (value) => setState(() => _mobility = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _communication,
              decoration: const InputDecoration(labelText: 'Communication (optional)', border: OutlineInputBorder()),
              items: Communication.all
                  .map((c) => DropdownMenuItem(value: c, child: Text(Communication.displayNames[c] ?? c)))
                  .toList(),
              onChanged: (value) => setState(() => _communication = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _feedingType,
              decoration: const InputDecoration(labelText: 'Feeding (optional)', border: OutlineInputBorder()),
              items: FeedingType.all
                  .map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f)))
                  .toList(),
              onChanged: (value) => setState(() => _feedingType = value),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Medicine (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: MedicalAssistance.all,
              labels: MedicalAssistance.displayNames,
              selected: _medicalAssistance,
              onChanged: (next) => setState(() {
                _medicalAssistance
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Has a medical condition?'),
              value: _hasMedicalCondition,
              onChanged: (value) => setState(() => _hasMedicalCondition = value),
            ),
            if (_hasMedicalCondition) ...[
              VitaMultiSelectChips(
                options: MedicalCondition.all,
                labels: MedicalCondition.displayNames,
                selected: _medicalConditions,
                onChanged: (next) => setState(() {
                  _medicalConditions
                    ..clear()
                    ..addAll(next);
                }),
              ),
              if (_medicalConditions.contains(MedicalCondition.other)) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _medicalConditionOtherController,
                  decoration: const InputDecoration(
                    labelText: 'Please describe the other condition',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            const Text('Toilet Assistance (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: ToiletAssistance.all,
              labels: ToiletAssistance.displayNames,
              selected: _toiletAssistance,
              onChanged: (next) => setState(() {
                _toiletAssistance
                  ..clear()
                  ..addAll(next);
              }),
            ),
            if (_toiletAssistance.contains(ToiletAssistance.others)) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _toiletAssistanceOtherController,
                decoration: const InputDecoration(
                  labelText: 'Please describe the other toilet assistance',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is regular vital monitoring required?'),
              value: _requiresVitalMonitoring,
              onChanged: (value) => setState(() => _requiresVitalMonitoring = value),
            ),
            if (_requiresVitalMonitoring)
              VitaMultiSelectChips(
                options: VitalMonitoringType.all,
                labels: VitalMonitoringType.displayNames,
                selected: _vitalMonitoringTypes,
                onChanged: (next) => setState(() {
                  _vitalMonitoringTypes
                    ..clear()
                    ..addAll(next);
                }),
              ),
            const SizedBox(height: AppSpacing.xl),
            const Text('Job Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: _cityKey,
              isExpanded: true,
              initialValue: _city,
              decoration: InputDecoration(
                labelText: 'City (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isCityValid ? 'Please select a city' : null,
              ),
              items: City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))).toList(),
              onChanged: (value) => setState(() => _city = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: _areaKey,
              controller: _areaController,
              focusNode: _areaFocusNode,
              decoration: InputDecoration(
                labelText: 'Area (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isAreaValid ? 'Area is required' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('About Nurse/Caregiver Requirement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: _dutyTypeKey,
              isExpanded: true,
              initialValue: _dutyType,
              decoration: InputDecoration(
                labelText: 'Hours Care Needed (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isDutyTypeValid ? 'Please select duty hours' : null,
              ),
              items: DutyType.all.map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d))).toList(),
              onChanged: (value) => setState(() => _dutyType = value),
            ),
            const SizedBox(height: AppSpacing.md),
            KeyedSubtree(
              key: _startDateKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preferred Start Date (Mandatory)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _showValidationErrors && !_isStartDateValid ? AppColors.error : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  OutlinedButton(
                    onPressed: _pickStartDate,
                    child: Text(
                      _startDate == null
                          ? 'Select date'
                          : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  if (_showValidationErrors && !_isStartDateValid)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Select a preferred start date', style: TextStyle(color: AppColors.error, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            KeyedSubtree(
              key: _languagesKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Language Preference (Mandatory)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _showValidationErrors && !_isLanguagesValid ? AppColors.error : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  VitaMultiSelectChips(
                    options: Language.all,
                    labels: Language.displayNames,
                    selected: _languages,
                    onChanged: (next) => setState(() {
                      _languages
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                  if (_showValidationErrors && !_isLanguagesValid)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Select at least one language', style: TextStyle(color: AppColors.error, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _preferredGender,
              decoration: const InputDecoration(labelText: 'Preferred Caregiver Gender', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('No preference')),
                DropdownMenuItem(value: Gender.male, child: Text('Male')),
                DropdownMenuItem(value: Gender.female, child: Text('Female')),
              ],
              onChanged: (value) => setState(() => _preferredGender = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _preferredReligion,
              decoration: const InputDecoration(labelText: 'Preferred Caregiver Religion', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('No preference')),
                ...[Religion.hindu, Religion.muslim, Religion.christian]
                    .map((r) => DropdownMenuItem(value: r, child: Text(_capitalize(r)))),
              ],
              onChanged: (value) => setState(() => _preferredReligion = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'More details you want to share about patient (optional)',
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

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
