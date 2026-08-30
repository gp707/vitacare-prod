import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../app/rate_card_button.dart';
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

// A UI-only sentinel — never sent to the backend as-is. Mutually exclusive
// with every real condition: picking a real condition drops this, picking
// this drops every real condition. Translated to
// `has_medical_condition: false` (and no `medical_conditions`) at
// submission time — the mandatory-but-can-be-none equivalent of
// _noPreferenceLanguage above.
const _noneMedicalCondition = 'none';
const _noneMedicalConditionLabel = 'None';

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
///
/// [cloneFrom], when supplied, pre-fills every field from a past
/// requirement (e.g. one the patient just cancelled and wants to repost)
/// — everything except [JobModel.startDate], which is deliberately left
/// blank since the source requirement's date has very likely already
/// passed, and never salary/frequency, which this form never collects at
/// all (admin sets them on approval, same as any other new posting). This
/// still always creates a brand-new job with its own id and its own
/// pending_review admin review — it's purely a form-prefill convenience.
class PostRequirementScreen extends ConsumerStatefulWidget {
  final JobModel? cloneFrom;

  const PostRequirementScreen({super.key, this.cloneFrom});

  @override
  ConsumerState<PostRequirementScreen> createState() => _PostRequirementScreenState();
}

class _PostRequirementScreenState extends ConsumerState<PostRequirementScreen> {
  final _ageController = TextEditingController();
  String? _gender;
  final _weightController = TextEditingController();
  String? _mobility;
  String? _feedingType;
  // Defaults to "None" — a real, deliberate choice, not an unset field
  // (see _noneMedicalCondition above). Mandatory: always holds at least one
  // value, so it can never be truly empty.
  final List<String> _medicalConditions = [_noneMedicalCondition];
  final _medicalConditionOtherController = TextEditingController();
  final List<String> _toiletAssistance = [];
  final _toiletAssistanceOtherController = TextEditingController();

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
  void initState() {
    super.initState();
    final source = widget.cloneFrom;
    if (source == null) return;
    final cr = source.careReceiver;
    if (cr != null) {
      _ageController.text = cr.age.toString();
      _gender = cr.gender;
      _weightController.text = cr.weightKg.toString();
      _mobility = cr.mobility;
      _feedingType = cr.feedingType;
      // Empty/false source means the source was itself "None" —
      // _medicalConditions already defaults to that, so leave it untouched.
      if (cr.hasMedicalCondition && cr.medicalConditions.isNotEmpty) {
        _medicalConditions
          ..clear()
          ..addAll(cr.medicalConditions);
      }
      _medicalConditionOtherController.text = cr.medicalConditionOther ?? '';
      _toiletAssistance.addAll(cr.toiletAssistance);
      _toiletAssistanceOtherController.text = cr.toiletAssistanceOther ?? '';
    }
    _city = source.city;
    _areaController.text = source.area ?? '';
    _descriptionController.text = source.description ?? '';
    _dutyType = source.dutyType;
    // start_date intentionally NOT carried over — the source requirement's
    // date has very likely already passed; the patient must pick a fresh
    // one (also avoids the date picker's initialDate < firstDate assert).
    // Empty source.languages means the source was itself "No Preference"
    // — _languages already defaults to that, so leave it untouched.
    if (source.languages.isNotEmpty) {
      _languages
        ..clear()
        ..addAll(source.languages);
    }
    _preferredGender = source.preferredGender;
    _preferredReligion = source.preferredReligion;
  }

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

  /// Purely advisory, never blocks submission — a male patient requesting
  /// a female caregiver is a much harder match to fill than any other
  /// combination, so we say so up front rather than letting the family
  /// find out only after posting.
  bool get _showGenderMismatchWarning => _gender == Gender.male && _preferredGender == Gender.female;

  /// Purely advisory, never blocks submission — picking any real language
  /// (rather than leaving it at "No Preference") narrows the caregiver pool
  /// down to just those who speak it, so we say so up front.
  bool get _showLanguagePreferenceWarning => !_languages.contains(_noPreferenceLanguage);

  /// Purely advisory, never blocks submission — same rationale as the
  /// language-preference warning above, for the same reason: a specific
  /// religion preference eliminates a large pool of candidates who could
  /// otherwise help the patient.
  bool get _showReligionPreferenceWarning => _preferredReligion != null;

  bool get _canSubmit =>
      !_saving &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isCityValid &&
      _isAreaValid &&
      _isDutyTypeValid &&
      _isStartDateValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one the patient/family sees when Submit scrolls them to it.
  /// Language Preference isn't here — it always defaults to "No
  /// Preference" and can never be empty, so it's never invalid.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid, focusNode: _weightFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_startDateKey, _isStartDateValid),
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
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

  /// "None" is mutually exclusive with every real condition: picking it
  /// clears any real selections, and picking a real condition clears
  /// "None". Deselecting the last real condition (or re-tapping "None"
  /// while it's the only thing selected) falls back to "None" — there's no
  /// truly-empty state, which is what makes this field mandatory without
  /// needing a separate red-highlight check. Must be called inside
  /// setState.
  void _applyMedicalConditionSelection(List<String> next) {
    final added = next.where((c) => !_medicalConditions.contains(c));
    final removed = _medicalConditions.where((c) => !next.contains(c));
    if (added.contains(_noneMedicalCondition)) {
      _medicalConditions
        ..clear()
        ..add(_noneMedicalCondition);
    } else if (added.isNotEmpty) {
      _medicalConditions
        ..clear()
        ..addAll(next.where((c) => c != _noneMedicalCondition));
    } else if (removed.isNotEmpty) {
      final remaining = next.where((c) => c != _noneMedicalCondition).toList();
      _medicalConditions
        ..clear()
        ..addAll(remaining.isEmpty ? [_noneMedicalCondition] : remaining);
    }
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
              feedingType: _feedingType,
              hasMedicalCondition: !_medicalConditions.contains(_noneMedicalCondition),
              medicalConditions:
                  _medicalConditions.contains(_noneMedicalCondition) ? null : _medicalConditions,
              medicalConditionOther: _medicalConditionOtherController.text.trim(),
              toiletAssistance: _toiletAssistance.isEmpty ? null : _toiletAssistance,
              toiletAssistanceOther: _toiletAssistanceOtherController.text.trim(),
            ),
            city: _city!,
            area: _areaController.text.trim(),
            description: _descriptionController.text.trim(),
            dutyType: _dutyType!,
            startDate: '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            languages: _languages.contains(_noPreferenceLanguage) ? [] : _languages,
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
      appBar: AppBar(
        title: Text(widget.cloneFrom != null ? 'Post Similar Requirement' : 'Post a Requirement'),
        actions: const [RateCardButton(), WhatsAppHelpButton()],
      ),
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
            const SizedBox(height: AppSpacing.xl),
            const Text('Care Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            const SizedBox(height: AppSpacing.md),
            const Text('Medical Condition (Mandatory)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: [_noneMedicalCondition, ...MedicalCondition.all],
              labels: {_noneMedicalCondition: _noneMedicalConditionLabel, ...MedicalCondition.displayNames},
              selected: _medicalConditions,
              onChanged: (next) => setState(() => _applyMedicalConditionSelection(next)),
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
              initialValue: _feedingType,
              decoration: const InputDecoration(labelText: 'Feeding (optional)', border: OutlineInputBorder()),
              items: FeedingType.all
                  .map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f)))
                  .toList(),
              onChanged: (value) => setState(() => _feedingType = value),
            ),
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
            const SizedBox(height: AppSpacing.xl),
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
                  if (_showLanguagePreferenceWarning) ...[
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
                              'A specific language preference may restrict potential candidates significantly.',
                              style: TextStyle(color: AppColors.warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
            if (_showReligionPreferenceWarning) ...[
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
                        'We strongly suggest No Preference for the religion. Selecting a specific '
                        'religion eliminates a large pool of candidates who could really help the patient.',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
