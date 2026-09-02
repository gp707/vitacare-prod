import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../../app/rate_card_button.dart';
import '../../../app/scope_of_work_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/individual_repository.dart';
import '../widgets/duty_requirements_button.dart';
import '../widgets/section_box.dart';

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

/// Two clearly-separated, boxed sections below a sticky Salary bar:
/// "Patient Details" (age, gender, weight, city, area, medical condition)
/// and "Care Preferences" (hours care needed, preferred start date,
/// duration care is needed, toilet assistance, feeding/medicine assistance,
/// preferred caregiver gender, language preference, preferred caregiver
/// religion). Salary — pre-filled from the Rate Card's suggested figure for
/// the derived care tier/frequency, see [deriveCareTier]/[suggestedRate],
/// but freely editable — lives in [_buildSalaryBar], pinned below the
/// AppBar so it's always visible regardless of scroll position; Frequency
/// of Care ([frequencyForCareDuration]) is no longer shown as its own field
/// anywhere on this form (it's still derived internally to pick the Salary
/// bar's ₹/day vs ₹/month unit and to submit frequency_of_care — patients
/// don't need to see it, only the resulting figure). Salary is no longer
/// admin-set on approval — the patient sees and can adjust it immediately,
/// same as nursenow-app's edit screen. Creates a pending_review requirement
/// (admin still reviews for legitimacy before it goes live, just no longer
/// sets pricing). Mobility and the free-text "more details" field are
/// deliberately not offered here at all (see CLAUDE.md's Mobility removal
/// note).
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
/// passed. Salary/Frequency are deliberately NOT cloned from the source's
/// old values either — they're freshly re-derived from whatever this new
/// posting's own fields end up being (which may differ from the source).
/// This still always creates a brand-new job with its own id and its own
/// pending_review admin review — it's purely a form-prefill convenience.
class PostRequirementScreen extends ConsumerStatefulWidget {
  final JobModel? cloneFrom;

  const PostRequirementScreen({super.key, this.cloneFrom});

  @override
  ConsumerState<PostRequirementScreen> createState() =>
      _PostRequirementScreenState();
}

class _PostRequirementScreenState extends ConsumerState<PostRequirementScreen> {
  final _ageController = TextEditingController();
  String? _gender;
  final _weightController = TextEditingController();
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
  String? _dutyType;
  DateTime? _startDate;
  String? _careDuration;
  // Defaults to "No Preference" — a real, deliberate choice, not an unset
  // field (see _noPreferenceLanguage above).
  final List<String> _languages = [_noPreferenceLanguage];
  String? _preferredGender;
  String? _preferredReligion;
  final _salaryController = TextEditingController();
  // Tracks the last suggestion we auto-filled into _salaryController, so a
  // relevant field change can safely refresh it — but only while the
  // patient hasn't typed anything of their own over it yet.
  String? _lastAutoSuggestedSalary;
  List<RateCardModel> _rateCards = const [];

  bool _saving = false;
  String? _error;

  // Only text-based mandatory fields need a FocusNode — that's what lets
  // Submit literally put the cursor in the first one that's missing.
  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _areaFocusNode = FocusNode();
  final _salaryFocusNode = FocusNode();

  // One key per mandatory field, in the order they appear on the form, so
  // Submit can scroll to whichever one is first still-invalid.
  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _startDateKey = GlobalKey();
  final _careDurationKey = GlobalKey();
  final _toiletAssistanceKey = GlobalKey();
  final _feedingTypeKey = GlobalKey();
  final _languagesKey = GlobalKey();
  final _salaryKey = GlobalKey();

  // Only turns true once Submit has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  @override
  void initState() {
    super.initState();
    final source = widget.cloneFrom;
    if (source != null) {
      final cr = source.careReceiver;
      if (cr != null) {
        _ageController.text = cr.age.toString();
        _gender = cr.gender;
        _weightController.text = cr.weightKg.toString();
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
      _dutyType = source.dutyType;
      _careDuration = source.careDuration;
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
    _loadRateCards();
  }

  /// Fire-and-forget — fetches the Rate Card once so Salary can be
  /// suggested as the patient fills in their care needs. Fails open: a
  /// network error just means no suggestion is offered, the field stays
  /// blank and freely editable either way.
  Future<void> _loadRateCards() async {
    try {
      final rateCards = await ref.read(rateCardRepositoryProvider).get();
      if (!mounted) return;
      setState(() => _rateCards = rateCards);
      _refreshSuggestedSalary();
    } catch (_) {
      // Fail open — see doc comment above.
    }
  }

  /// Rebuilds a [CareReceiverModel] from whatever's currently selected on
  /// this form, for [deriveCareTier] — communication/vitals aren't
  /// collected on this form at all, so they're just fixed at their
  /// server-side defaults (matches CARE_RECEIVER_DEFAULTS).
  CareReceiverModel get _careReceiverForTierDerivation => CareReceiverModel(
        id: '',
        age: _age ?? 0,
        gender: _gender ?? '',
        weightKg: _weightKg ?? 0,
        communication: Communication.verbal,
        feedingType: _feedingType ?? FeedingType.oralFeeding,
        hasMedicalCondition:
            !_medicalConditions.contains(_noneMedicalCondition),
        medicalConditions: _medicalConditions.contains(_noneMedicalCondition)
            ? const []
            : _medicalConditions,
        toiletAssistance: _toiletAssistance,
        requiresVitalMonitoring: false,
        vitalMonitoringTypes: const [],
      );

  /// Recomputes the suggested Salary from the current Duration Care is
  /// Needed + care-tier selections and, if it changed, refills the field —
  /// but only when the field is still empty or still holds our own
  /// previous suggestion, never overwriting something the patient typed
  /// themselves. Call after any change to _careDuration/_toiletAssistance/
  /// _feedingType/_medicalConditions.
  void _refreshSuggestedSalary() {
    if (_careDuration == null) return;
    final tier = deriveCareTier(_careReceiverForTierDerivation);
    final frequency = frequencyForCareDuration(_careDuration!);
    final suggestion = suggestedRate(_rateCards, tier, frequency);
    if (suggestion == null) return;
    if (_salaryController.text.isEmpty ||
        _salaryController.text == _lastAutoSuggestedSalary) {
      _salaryController.text = suggestion;
      _lastAutoSuggestedSalary = suggestion;
    }
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _areaController.dispose();
    _salaryController.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _areaFocusNode.dispose();
    _salaryFocusNode.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());

  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid =>
      _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isStartDateValid => _startDate != null;
  bool get _isCareDurationValid => _careDuration != null;
  bool get _isToiletAssistanceValid => _toiletAssistance.isNotEmpty;
  bool get _isFeedingTypeValid => _feedingType != null;
  bool get _isSalaryValid => _salaryController.text.trim().isNotEmpty;

  /// Few Days/Few Weeks price off the daily Rate Card, Few Months/Long Term
  /// off the monthly one — see [frequencyForCareDuration].
  String? get _derivedFrequencyOfCare =>
      _careDuration == null ? null : frequencyForCareDuration(_careDuration!);

  /// Purely advisory, never blocks submission — a male patient requesting
  /// a female caregiver is a much harder match to fill than any other
  /// combination, so we say so up front rather than letting the family
  /// find out only after posting.
  bool get _showGenderMismatchWarning =>
      _gender == Gender.male && _preferredGender == Gender.female;

  /// Purely advisory, never blocks submission — picking any real language
  /// (rather than leaving it at "No Preference") narrows the caregiver pool
  /// down to just those who speak it, so we say so up front.
  bool get _showLanguagePreferenceWarning =>
      !_languages.contains(_noPreferenceLanguage);

  /// Purely advisory, never blocks submission — same rationale as the
  /// language-preference warning above, for the same reason: a specific
  /// religion preference eliminates a large pool of candidates who could
  /// otherwise help the patient.
  bool get _showReligionPreferenceWarning => _preferredReligion != null;

  /// Purely advisory, never blocks submission — many nurses decline
  /// short-term (few days/weeks) assignments, so the family is warned up
  /// front that they may get fewer or no applicants, with a suggestion to
  /// edit to a longer duration later if that happens.
  bool get _showShortTermDurationWarning =>
      _careDuration == CareDuration.fewDays ||
      _careDuration == CareDuration.fewWeeks;

  bool get _canSubmit =>
      !_saving &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isCityValid &&
      _isAreaValid &&
      _isDutyTypeValid &&
      _isStartDateValid &&
      _isCareDurationValid &&
      _isToiletAssistanceValid &&
      _isFeedingTypeValid &&
      _isSalaryValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one the patient/family sees when Submit scrolls them to it —
  /// Patient Details' fields before Care Preferences' before Nurse Fee
  /// Guidance's, matching the section order on screen. Language Preference
  /// isn't here — it always defaults to "No Preference" and can never be
  /// empty, so it's never invalid.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid,
            focusNode: _weightFocusNode),
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_startDateKey, _isStartDateValid),
        _MandatoryField(_careDurationKey, _isCareDurationValid),
        _MandatoryField(_toiletAssistanceKey, _isToiletAssistanceValid),
        _MandatoryField(_feedingTypeKey, _isFeedingTypeValid),
        _MandatoryField(_salaryKey, _isSalaryValid,
            focusNode: _salaryFocusNode),
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
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Focus first — on mobile this opens the on-screen keyboard,
          // which shrinks the viewport. Doing this *before* computing where
          // to scroll (and waiting for the keyboard's resize to settle)
          // means ensureVisible scrolls against the final, keyboard-shrunk
          // viewport size; doing it the other way around (the previous
          // order here) let the keyboard's later resize cover the field
          // right after the scroll had already placed it in view, which is
          // why this worked on desktop/web (no on-screen keyboard) but not
          // on an actual phone.
          target.focusNode?.requestFocus();
          if (target.focusNode != null) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
          final ctx = target.key.currentContext;
          if (ctx != null && ctx.mounted) {
            await Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
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
              feedingType: _feedingType,
              hasMedicalCondition:
                  !_medicalConditions.contains(_noneMedicalCondition),
              medicalConditions:
                  _medicalConditions.contains(_noneMedicalCondition)
                      ? null
                      : _medicalConditions,
              medicalConditionOther:
                  _medicalConditionOtherController.text.trim(),
              toiletAssistance:
                  _toiletAssistance.isEmpty ? null : _toiletAssistance,
              toiletAssistanceOther:
                  _toiletAssistanceOtherController.text.trim(),
            ),
            city: _city!,
            area: _areaController.text.trim(),
            dutyType: _dutyType!,
            startDate:
                '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            careDuration: _careDuration!,
            languages:
                _languages.contains(_noPreferenceLanguage) ? [] : _languages,
            preferredGender: _preferredGender,
            preferredReligion: _preferredReligion,
            frequencyOfCare: _derivedFrequencyOfCare!,
            salaryAmount: _salaryController.text.trim(),
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
        title: Text(widget.cloneFrom != null
            ? 'Post Similar Requirement'
            : 'Post a Requirement'),
        actions: const [RateCardButton(), WhatsAppHelpButton()],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSalaryBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  SectionBox(
                    icon: Icons.person,
                    title: 'Patient Details',
                    children: [
                      TextField(
                        key: _ageKey,
                        controller: _ageController,
                        focusNode: _ageFocusNode,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.cake),
                          labelText: "Patient's Age (Mandatory)",
                          border: const OutlineInputBorder(),
                          errorText: _showValidationErrors && !_isAgeValid
                              ? 'Age is required (1-120)'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _genderKey,
                        isExpanded: true,
                        initialValue: _gender,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.wc),
                          labelText: "Patient's Gender (Mandatory)",
                          border: const OutlineInputBorder(),
                          errorText: _showValidationErrors && !_isGenderValid
                              ? 'Please select a gender'
                              : null,
                        ),
                        items: Gender.all
                            .map((g) => DropdownMenuItem(
                                value: g, child: Text(_capitalize(g))))
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
                          prefixIcon: const Icon(Icons.monitor_weight_outlined),
                          labelText: "Patient's Weight (kg) (Mandatory)",
                          border: const OutlineInputBorder(),
                          errorText: _showValidationErrors && !_isWeightValid
                              ? 'Weight is required (1-300 kg)'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _cityKey,
                        isExpanded: true,
                        initialValue: _city,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.location_city),
                          labelText: 'City (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText: _showValidationErrors && !_isCityValid
                              ? 'Please select a city'
                              : null,
                        ),
                        items: City.all
                            .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(City.displayNames[c] ?? c)))
                            .toList(),
                        onChanged: (value) => setState(() => _city = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        key: _areaKey,
                        controller: _areaController,
                        focusNode: _areaFocusNode,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.location_on),
                          labelText: 'Area (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText: _showValidationErrors && !_isAreaValid
                              ? 'Area is required'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Row(
                        children: [
                          Icon(Icons.medical_information, size: 18, color: AppColors.primaryDark),
                          SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text('Medical Condition (Mandatory)', style: SectionBox.fieldGroupLabelStyle),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      VitaMultiSelectChips(
                        options: [
                          _noneMedicalCondition,
                          ...MedicalCondition.all
                        ],
                        labels: {
                          _noneMedicalCondition: _noneMedicalConditionLabel,
                          ...MedicalCondition.displayNames
                        },
                        selected: _medicalConditions,
                        onChanged: (next) => setState(() {
                          _applyMedicalConditionSelection(next);
                          _refreshSuggestedSalary();
                        }),
                      ),
                      if (_medicalConditions
                          .contains(MedicalCondition.other)) ...[
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
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionBox(
                    icon: Icons.tune,
                    title: 'Care Preferences',
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: _dutyTypeKey,
                              isExpanded: true,
                              initialValue: _dutyType,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.access_time),
                                labelText: 'Hours Care Needed (Mandatory)',
                                border: const OutlineInputBorder(),
                                errorText:
                                    _showValidationErrors && !_isDutyTypeValid
                                        ? 'Please select duty hours'
                                        : null,
                              ),
                              items: DutyType.all
                                  .map((d) => DropdownMenuItem(
                                      value: d,
                                      child:
                                          Text(DutyType.displayNames[d] ?? d)))
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _dutyType = value),
                            ),
                          ),
                          DutyRequirementsInfoButton(dutyType: _dutyType),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      KeyedSubtree(
                        key: _startDateKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: _showValidationErrors && !_isStartDateValid
                                      ? AppColors.error
                                      : AppColors.primaryDark,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Flexible(
                                  child: Text(
                                    'Preferred Start Date (Mandatory)',
                                    style: SectionBox.fieldGroupLabelStyle.copyWith(
                                      color: _showValidationErrors && !_isStartDateValid
                                          ? AppColors.error
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            OutlinedButton.icon(
                              onPressed: _pickStartDate,
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                _startDate == null
                                    ? 'Select date'
                                    : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                              ),
                            ),
                            if (_showValidationErrors && !_isStartDateValid)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text('Select a preferred start date',
                                    style: TextStyle(
                                        color: AppColors.error, fontSize: AppTypography.small)),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _careDurationKey,
                        isExpanded: true,
                        initialValue: _careDuration,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.timelapse),
                          labelText: 'How long you need the care for? (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText:
                              _showValidationErrors && !_isCareDurationValid
                                  ? 'Please select how long care is needed'
                                  : null,
                        ),
                        items: CareDuration.all
                            .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(CareDuration.displayNames[d] ?? d)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _careDuration = value;
                          _refreshSuggestedSalary();
                        }),
                      ),
                      if (_showShortTermDurationWarning) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            border: Border.all(color: AppColors.warning),
                            borderRadius: BorderRadius.circular(AppSpacing.sm),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber,
                                  color: AppColors.warning, size: 20),
                              SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Short-term requirement',
                                      style: TextStyle(
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Many nurses do not accept short-term assignments. You can '
                                      'continue with this requirement, but you may receive fewer '
                                      "or no applicants. If you don't find a suitable nurse, you "
                                      'may edit this job to "Need for minimum a month".',
                                      style:
                                          TextStyle(color: AppColors.warning),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _toiletAssistanceKey,
                        isExpanded: true,
                        initialValue: _toiletAssistance.isEmpty
                            ? null
                            : _toiletAssistance.first,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.wash),
                          labelText: 'Toilet Assistance (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText:
                              _showValidationErrors && !_isToiletAssistanceValid
                                  ? 'Please select toilet assistance'
                                  : null,
                        ),
                        items: ToiletAssistance.all
                            .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                    ToiletAssistance.displayNames[t] ?? t)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _toiletAssistance
                            ..clear()
                            ..add(value!);
                          _refreshSuggestedSalary();
                        }),
                      ),
                      if (_toiletAssistance
                          .contains(ToiletAssistance.others)) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _toiletAssistanceOtherController,
                          decoration: const InputDecoration(
                            labelText:
                                'Please describe the other toilet assistance',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        key: _feedingTypeKey,
                        isExpanded: true,
                        initialValue: _feedingType,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.restaurant),
                          labelText: 'Feeding/Medicine Assistance (Mandatory)',
                          border: const OutlineInputBorder(),
                          errorText:
                              _showValidationErrors && !_isFeedingTypeValid
                                  ? 'Please select feeding/medicine assistance'
                                  : null,
                        ),
                        items: FeedingType.all
                            .map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(FeedingType.displayNames[f] ?? f)))
                            .toList(),
                        onChanged: (value) => setState(() {
                          _feedingType = value;
                          _refreshSuggestedSalary();
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _preferredGender,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.people_outline),
                            labelText: 'Preferred Caregiver Gender',
                            border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(
                              value: null, child: Text('No preference')),
                          DropdownMenuItem(
                              value: Gender.male, child: Text('Male')),
                          DropdownMenuItem(
                              value: Gender.female, child: Text('Female')),
                        ],
                        onChanged: (value) =>
                            setState(() => _preferredGender = value),
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
                              Icon(Icons.warning_amber,
                                  color: AppColors.warning, size: 20),
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
                      KeyedSubtree(
                        key: _languagesKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.language, size: 18, color: AppColors.primaryDark),
                                SizedBox(width: AppSpacing.xs),
                                Flexible(
                                  child: Text('Language Preference', style: SectionBox.fieldGroupLabelStyle),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            VitaMultiSelectChips(
                              options: [_noPreferenceLanguage, ...Language.all],
                              labels: {
                                _noPreferenceLanguage:
                                    _noPreferenceLanguageLabel,
                                ...Language.displayNames
                              },
                              selected: _languages,
                              onChanged: (next) =>
                                  setState(() => _applyLanguageSelection(next)),
                            ),
                            if (_showLanguagePreferenceWarning) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.1),
                                  border: Border.all(color: AppColors.warning),
                                  borderRadius:
                                      BorderRadius.circular(AppSpacing.sm),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber,
                                        color: AppColors.warning, size: 20),
                                    SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        'A specific language preference may restrict potential candidates significantly.',
                                        style:
                                            TextStyle(color: AppColors.warning),
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
                        initialValue: _preferredReligion,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.diversity_3),
                            labelText: 'Preferred Caregiver Religion',
                            border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('No preference')),
                          ...[
                            Religion.hindu,
                            Religion.muslim,
                            Religion.christian
                          ].map((r) => DropdownMenuItem(
                              value: r, child: Text(_capitalize(r)))),
                        ],
                        onChanged: (value) =>
                            setState(() => _preferredReligion = value),
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
                              Icon(Icons.warning_amber,
                                  color: AppColors.warning, size: 20),
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
                    ],
                  ),
                  // Nurse Fee Guidance section removed — Salary now lives in the
                  // sticky top bar (see _buildSalaryBar) instead of buried at the
                  // bottom of the form; Frequency of Care is no longer shown at
                  // all (still derived internally via _derivedFrequencyOfCare to
                  // pick the Salary unit and to submit frequency_of_care).
                  const SizedBox(height: AppSpacing.lg),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _handleSubmitPressed,
                    icon: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 18),
                    label: const Text('Submit for Review'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sticky bar pinned below the AppBar (a sibling of the scrollable
  /// content, not inside it) so Salary — the one figure that actually
  /// matters now that Frequency of Care is no longer shown as its own
  /// field — stays visible no matter how far the form is scrolled.
  /// Frequency of Care is still derived internally (see
  /// _derivedFrequencyOfCare) purely to pick the ₹/day vs ₹/month unit and
  /// to submit frequency_of_care — it's just never displayed on its own.
  ///
  /// The Salary input itself only appears once Duration Care is Needed,
  /// Toilet Assistance, and Feeding/Medicine Assistance are all filled in —
  /// exactly the 3 fields the derived tier/frequency (and therefore the
  /// Rate Card suggestion) depend on — a placeholder hint fills the bar
  /// until then instead of showing an input with nothing meaningful to
  /// suggest yet.
  ///
  /// Styled as a bold yellow ribbon (solid fill, rounded bottom corners, a
  /// drop shadow to lift it off the page) rather than a plain bordered box
  /// — this is the single most important figure on the form, so it reads
  /// as a banner the patient can't miss, not just another field. No icon or
  /// "SALARY" heading above the input — the field's own label already says
  /// "Salary". The field is still mandatory for submission (_isSalaryValid
  /// still gates Submit) — "(Negotiable)" in its label is purely a wording
  /// choice, not a validation change, matching the "You can always
  /// negotiate with nurse staff." caption below it.
  Widget _buildSalaryBar() {
    final ready =
        _isCareDurationValid && _isToiletAssistanceValid && _isFeedingTypeValid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.amber,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: !ready
          ? const Text(
              'Salary will appear here once how long you need the care for, Toilet '
              'Assistance, and Feeding/Medicine Assistance are filled in.',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppTypography.small,
                  fontWeight: FontWeight.w500),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pre-filled with the Rate Card's suggested figure for the
                // derived care tier + frequency once it's available (see
                // _refreshSuggestedSalary), refreshed as related fields
                // change — but never overwriting something the patient
                // already typed themselves. Free text, not a number, so it
                // can carry a range or a note exactly as admin wrote it in
                // the Rate Card.
                TextField(
                  key: _salaryKey,
                  controller: _salaryController,
                  focusNode: _salaryFocusNode,
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText:
                        'Salary (₹/${_derivedFrequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}) (Negotiable)',
                    filled: true,
                    fillColor: Colors.white,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _showValidationErrors && !_isSalaryValid
                        ? 'Salary is required'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildDerivedTierLine(),
              ],
            ),
    );
  }

  /// "Based on the requirements you entered, this appears to be a
  /// `<tier>`." with the tier name itself tappable — opens the same Scope of
  /// Work dialog [ScopeOfWorkButton] uses elsewhere, for the exact tier
  /// [deriveCareTier] derives from the form's current selections, right
  /// where the patient can see it alongside the salary it drove. A plain
  /// GestureDetector+Text pair rather than a RichText TextSpan recognizer,
  /// so there's no GestureRecognizer lifecycle to manage.
  Widget _buildDerivedTierLine() {
    final tier = deriveCareTier(_careReceiverForTierDerivation);
    final tierLabel = CareTier.displayNames[tier] ?? tier;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Based on the requirements you entered, this appears to be a ',
          style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.small),
        ),
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => ScopeOfWorkDialog(
              tier: tier,
              repository: ref.read(scopeOfWorkRepositoryProvider),
            ),
          ),
          child: Text(
            tierLabel,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: AppTypography.small,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const Text('.',
            style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.small)),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
