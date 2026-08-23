import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/individual_repository.dart';

// A UI-only sentinel — never sent to the backend as-is. Mutually exclusive
// with every real language: picking a real language drops this, picking
// this drops every real language. Translated to an empty `languages: []`
// array at submission time, which the backend treats as "No Preference"
// (see CreateIndividualRequirementDto/UpdateIndividualRequirementDto).
const _noPreferenceLanguage = 'no_preference';
const _noPreferenceLanguageLabel = 'No Preference';

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Same fields as PostRequirementScreen (pre-filled from [requirement]),
/// plus Frequency of Care + Salary once the requirement has been through
/// at least one admin approval ([requirement].frequencyOfCare non-null) —
/// before that, admin hasn't set them yet, so there's nothing to edit
/// there (JOB_013 server-side if attempted). Allowed regardless of the
/// requirement's current status (pending_review/active/closed); the
/// screen that opens this is responsible for not offering Edit at all
/// while there's an active application (JOB_014 is the server-side
/// backstop — see JobsPostedScreen's _RequirementCard).
///
/// Editing never requires admin re-review and never changes status — any
/// number of edits are allowed, before or after admin's first approval.
class EditRequirementScreen extends ConsumerStatefulWidget {
  final JobModel requirement;

  const EditRequirementScreen({super.key, required this.requirement});

  @override
  ConsumerState<EditRequirementScreen> createState() => _EditRequirementScreenState();
}

class _EditRequirementScreenState extends ConsumerState<EditRequirementScreen> {
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
  // Defaults to "No Preference" — a real, deliberate choice, not an unset
  // field (see _noPreferenceLanguage above).
  final List<String> _languages = [_noPreferenceLanguage];
  String? _preferredGender;
  String? _preferredReligion;

  // Only present at all once the requirement has been reviewed once —
  // see _canEditSalaryFrequency.
  String? _frequencyOfCare;
  final _salaryController = TextEditingController();

  bool _saving = false;
  String? _error;

  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _areaFocusNode = FocusNode();
  final _salaryFocusNode = FocusNode();

  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _startDateKey = GlobalKey();
  final _languagesKey = GlobalKey();
  final _frequencyKey = GlobalKey();
  final _salaryKey = GlobalKey();

  bool _showValidationErrors = false;

  bool get _canEditSalaryFrequency => widget.requirement.frequencyOfCare != null;

  @override
  void initState() {
    super.initState();
    final job = widget.requirement;
    final cr = job.careReceiver;
    if (cr != null) {
      _ageController.text = cr.age.toString();
      _gender = cr.gender;
      _weightController.text = cr.weightKg.toString();
      _mobility = cr.mobility;
      _communication = cr.communication;
      _feedingType = cr.feedingType;
      _medicalAssistance.addAll(cr.medicalAssistance);
      _hasMedicalCondition = cr.hasMedicalCondition;
      _medicalConditions.addAll(cr.medicalConditions);
      _medicalConditionOtherController.text = cr.medicalConditionOther ?? '';
      _toiletAssistance.addAll(cr.toiletAssistance);
      _toiletAssistanceOtherController.text = cr.toiletAssistanceOther ?? '';
      _requiresVitalMonitoring = cr.requiresVitalMonitoring;
      _vitalMonitoringTypes.addAll(cr.vitalMonitoringTypes);
    }
    _city = job.city;
    _areaController.text = job.area ?? '';
    _descriptionController.text = job.description ?? '';
    _dutyType = job.dutyType;
    _startDate = job.startDate == null ? null : DateTime.tryParse(job.startDate!);
    // Empty job.languages means the job was itself "No Preference" —
    // _languages already defaults to that, so leave it untouched.
    if (job.languages.isNotEmpty) {
      _languages
        ..clear()
        ..addAll(job.languages);
    }
    _preferredGender = job.preferredGender;
    _preferredReligion = job.preferredReligion;
    _frequencyOfCare = job.frequencyOfCare;
    _salaryController.text = job.salaryAmount?.toString() ?? '';
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _areaController.dispose();
    _descriptionController.dispose();
    _salaryController.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _areaFocusNode.dispose();
    _salaryFocusNode.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());
  int? get _salaryAmount => int.tryParse(_salaryController.text.trim());

  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid => _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isStartDateValid => _startDate != null;

  /// Purely advisory, never blocks submission — a male patient requesting
  /// a female caregiver is a much harder match to fill than any other
  /// combination, so we say so up front rather than letting the family
  /// find out only after posting.
  bool get _showGenderMismatchWarning => _gender == Gender.male && _preferredGender == Gender.female;
  bool get _isFrequencyValid => !_canEditSalaryFrequency || _frequencyOfCare != null;
  bool get _isSalaryValid =>
      !_canEditSalaryFrequency || (_salaryAmount != null && _salaryAmount! >= 1 && _salaryAmount! <= 1000000);

  bool get _canSubmit =>
      !_saving &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isCityValid &&
      _isAreaValid &&
      _isDutyTypeValid &&
      _isStartDateValid &&
      _isFrequencyValid &&
      _isSalaryValid;

  /// Language Preference isn't here — it always defaults to "No
  /// Preference" and can never be empty, so it's never invalid.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid, focusNode: _weightFocusNode),
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_startDateKey, _isStartDateValid),
        if (_canEditSalaryFrequency) _MandatoryField(_frequencyKey, _isFrequencyValid),
        if (_canEditSalaryFrequency) _MandatoryField(_salaryKey, _isSalaryValid, focusNode: _salaryFocusNode),
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

  /// "No Preference" is mutually exclusive with every real language:
  /// picking it clears any real selections, and picking a real language
  /// clears "No Preference". Deselecting the last real language (or
  /// re-tapping "No Preference" while it's the only thing selected) falls
  /// back to "No Preference" — there's no truly-empty state. Must be
  /// called inside setState.
  void _applyLanguageSelection(List<String> next) {
    final added = next.where((l) => !_languages.contains(l));
    final removed = _languages.where((l) => !next.contains(l));
    if (added.contains(_noPreferenceLanguage)) {
      _languages
        ..clear()
        ..add(_noPreferenceLanguage);
    } else if (added.isNotEmpty) {
      _languages
        ..clear()
        ..addAll(next.where((l) => l != _noPreferenceLanguage));
    } else if (removed.isNotEmpty) {
      final remaining = next.where((l) => l != _noPreferenceLanguage).toList();
      _languages
        ..clear()
        ..addAll(remaining.isEmpty ? [_noPreferenceLanguage] : remaining);
    }
  }

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
      await ref.read(individualRepositoryProvider).editRequirement(
            widget.requirement.id,
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
            languages: _languages.contains(_noPreferenceLanguage) ? [] : _languages,
            preferredGender: _preferredGender,
            preferredReligion: _preferredReligion,
            frequencyOfCare: _canEditSalaryFrequency ? _frequencyOfCare : null,
            salaryAmount: _canEditSalaryFrequency ? _salaryAmount : null,
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
      appBar: AppBar(title: const Text('Edit Requirement'), actions: const [WhatsAppHelpButton()]),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
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
                  const Text('Language Preference', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  VitaMultiSelectChips(
                    options: [_noPreferenceLanguage, ...Language.all],
                    labels: {_noPreferenceLanguage: _noPreferenceLanguageLabel, ...Language.displayNames},
                    selected: _languages,
                    onChanged: (next) => setState(() => _applyLanguageSelection(next)),
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
            if (_showGenderMismatchWarning) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  border: Border.all(color: AppColors.warning),
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Requesting a female caregiver for a male patient reduces your chances of '
                        'getting matched by about 90%.',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
            // Only shown once admin has approved this requirement at least
            // once — before that there's nothing to edit here yet (admin
            // sets these for the first time, same as at initial approval).
            if (_canEditSalaryFrequency) ...[
              const SizedBox(height: AppSpacing.xl),
              const Text('Frequency & Salary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                key: _frequencyKey,
                isExpanded: true,
                initialValue: _frequencyOfCare,
                decoration: InputDecoration(
                  labelText: 'Frequency of Care (Mandatory)',
                  border: const OutlineInputBorder(),
                  errorText: _showValidationErrors && !_isFrequencyValid ? 'Please select a frequency' : null,
                ),
                items: FrequencyOfCare.all
                    .map((f) => DropdownMenuItem(value: f, child: Text(FrequencyOfCare.displayNames[f] ?? f)))
                    .toList(),
                onChanged: (value) => setState(() => _frequencyOfCare = value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: _salaryKey,
                controller: _salaryController,
                focusNode: _salaryFocusNode,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Salary (₹/${_frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}) (Mandatory)',
                  border: const OutlineInputBorder(),
                  errorText: _showValidationErrors && !_isSalaryValid ? 'Salary is required (1-1,000,000)' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
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
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
