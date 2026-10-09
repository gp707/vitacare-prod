import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/rate_card_button.dart';
import '../../../app/scope_of_work_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../app/whatsapp_help_button.dart';
import '../../individual/data/individual_repository.dart';
import '../../individual/widgets/area_char_limit_note.dart';
import '../../individual/widgets/duty_requirements_button.dart';
import '../../individual/widgets/section_box.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';

// organisation_profiles.city accepts the existing 7 cities plus this one
// extra sentinel — a separate org-scoped list, not an extension of the
// shared City enum (see "NurseNow" in CLAUDE.md).
const _organisationCityOthers = 'others';

// Each account type has its own Terms & Conditions document (an org's
// legal terms differ from an individual/family's) — the checkbox links out
// to whichever one matches the currently-selected account type.
// /preview, not /edit — a plain public read-only viewer that never prompts
// for a Google account, unlike /edit which routes through the Docs editor
// UI (expects an account context, and shows "could not find any Google
// account" on a device signed into none).
const _individualTermsUrl =
    'https://docs.google.com/document/d/1TvqDSP5EZRh8ZtxLhRH_b46J7Q-6cIV5VCUsTkH1Q5s/preview';
const _organisationTermsUrl =
    'https://docs.google.com/document/d/1y_o29xiumKqmzshox58vGcYYFnWVUKWL6cd6m_Eycpw/preview';

// A UI-only sentinel — never sent to the backend as-is. Mutually exclusive
// with every real language: picking a real language drops this, picking
// this drops every real language. Translated to an empty `languages: []`
// array at submission time, which the backend treats as "No Preference"
// (see CreateIndividualRequirementDto).
const _noPreferenceLanguage = 'no_preference';

// A UI-only sentinel — never sent to the backend as-is. Mutually exclusive
// with every real condition: picking a real condition drops this, picking
// this drops every real condition. Translated to
// `has_medical_condition: false` (and no `medical_conditions`) at
// submission time — the mandatory-but-can-be-none equivalent of
// _noPreferenceLanguage above.
const _noneMedicalCondition = 'none';
const _noneMedicalConditionLabel = 'None';

// A UI-only sentinel — never sent to the backend as-is, and never fed into
// deriveCareTier()/the Rate Card lookup as-is either. Translated to
// FeedingType.oralFeeding (same salary guidance, same tier) everywhere
// it's read from. See _effectiveFeedingType.
const _noneFeedingType = 'none';
const _noneFeedingTypeLabel = 'None';

// Same idea as _noneFeedingType above, for Toilet Assistance — translated
// to ToiletAssistance.independent (same salary guidance, same tier)
// everywhere it's read from. See _effectiveToiletAssistance.
const _noneToiletAssistance = 'none';
const _noneToiletAssistanceLabel = 'None';

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Flow: phone -> PIN -> (Individual: the full care-requirement form,
/// same fields that used to live on a separate "Post a Requirement"
/// screen; Organisation: contact/org name/type/city/area) -> Terms &
/// Conditions -> submit. Account type itself is fixed on entry
/// (widget.startAsOrganisation), not chosen on this screen.
///
/// Posting a requirement is no longer a separate step reachable after
/// registration — it IS registration, for Individual accounts. Submitting
/// this form registers the account and creates its one requirement in a
/// single action (the button reads "Post Requirement" for that branch).
/// Since a phone number can only ever register once (AUTH_001/AUTH_016),
/// this means an individual can only ever post exactly one requirement in
/// the lifetime of that phone number — there is no "post a new one later"
/// entry point anywhere else in the app any more (JobsPostedScreen no
/// longer has a Post CTA or a Post Similar action; every field on the one
/// requirement already posted stays directly editable right there on its
/// own card, which is not the same as posting a new one).
///
/// Submit is always tappable (mirrors admin-web's job-posting form and the
/// old standalone PostRequirementScreen): if a mandatory field is missing,
/// tapping it flags every missing mandatory field red and scrolls/focuses
/// straight to the first one instead of submitting.
class RegistrationScreen extends ConsumerStatefulWidget {
  /// Fixes this registration as Organisation vs. Individual for the whole
  /// screen's lifetime — set from which row the login screen's "New here?
  /// Register as:" section was reached through (Patient = false,
  /// Organisation = true), the only way this form is ever opened.
  final bool startAsOrganisation;

  const RegistrationScreen({super.key, this.startAsOrganisation = false});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _verificationToken;
  bool _termsAccepted = false;
  bool _loading = false;
  String? _errorMessage;

  final _phoneFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();

  final _phoneKey = GlobalKey();
  final _codeKey = GlobalKey();
  final _termsKey = GlobalKey();

  // --- Organisation-only fields ---
  final _fullNameController = TextEditingController();
  final _organisationNameController = TextEditingController();
  final _organisationAreaController = TextEditingController();
  final _fullNameFocusNode = FocusNode();
  final _organisationNameFocusNode = FocusNode();
  final _fullNameKey = GlobalKey();
  final _organisationNameKey = GlobalKey();
  final _organisationTypeKey = GlobalKey();
  final _organisationCityKey = GlobalKey();
  String? _organisationType;
  String? _organisationCity;

  // --- Individual-only fields: the full care-requirement form, merged in
  // from the old standalone PostRequirementScreen. ---
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
  final _careDurationKey = GlobalKey();
  final _toiletAssistanceKey = GlobalKey();
  final _feedingTypeKey = GlobalKey();
  final _salaryKey = GlobalKey();

  // Only turns true once Register has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  bool get _isOrganisation => widget.startAsOrganisation;

  String get _phone => '+91${_phoneController.text.trim()}';
  bool get _otpMode => ref.read(otpModeProvider);

  @override
  void initState() {
    super.initState();
    if (!_isOrganisation) _loadRateCards();
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

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _otpController.dispose();
    _phoneFocusNode.dispose();
    _codeFocusNode.dispose();
    _fullNameController.dispose();
    _organisationNameController.dispose();
    _organisationAreaController.dispose();
    _fullNameFocusNode.dispose();
    _organisationNameFocusNode.dispose();
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

  Future<void> _sendRegistrationOtp() async {
    if (!_isPhoneValid) {
      setState(() => _showValidationErrors = true);
      return;
    }
    setState(() => _sendingOtp = true);
    try {
      await ref.read(authRepositoryProvider).sendOtp(phone: _phone, purpose: OtpPurpose.register);
      if (mounted) setState(() => _otpSent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyRegistrationOtp() async {
    if (!Validators.isValidOtp(_otpController.text.trim())) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _verifyingOtp = true;
      _errorMessage = null;
    });
    try {
      final token = await ref.read(authRepositoryProvider).verifyOtp(
            phone: _phone,
            otp: _otpController.text.trim(),
            purpose: OtpPurpose.register,
          );
      if (mounted) setState(() => _verificationToken = token);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  bool get _isPhoneValid => Validators.isValidPhone(_phone);
  bool get _isCodeValid => _otpMode ? _verificationToken != null : Validators.isValidCode(_codeController.text.trim());
  bool get _isTermsValid => _termsAccepted;

  String get _termsUrl => _isOrganisation ? _organisationTermsUrl : _individualTermsUrl;

  Future<void> _openTerms() => launchUrl(Uri.parse(_termsUrl), mode: LaunchMode.externalApplication);

  // --- Organisation-only validity ---
  bool get _isFullNameValid => !_isOrganisation || Validators.isValidName(_fullNameController.text.trim());
  bool get _isOrganisationNameValid => !_isOrganisation || _organisationNameController.text.trim().isNotEmpty;
  bool get _isOrganisationTypeValid => !_isOrganisation || _organisationType != null;
  bool get _isOrganisationCityValid => !_isOrganisation || _organisationCity != null;

  // --- Individual-only validity (the merged-in requirement form) ---
  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());

  bool get _isAgeValid => _isOrganisation || (_age != null && _age! >= 1 && _age! <= 120);
  bool get _isGenderValid => _isOrganisation || _gender != null;
  bool get _isWeightValid => _isOrganisation || (_weightKg != null && _weightKg! >= 1 && _weightKg! <= 300);
  bool get _isCityValid => _isOrganisation || _city != null;
  bool get _isAreaValid => _isOrganisation || _areaController.text.trim().isNotEmpty;
  bool get _isDutyTypeValid => _isOrganisation || _dutyType != null;
  bool get _isStartDateValid => _isOrganisation || _startDate != null;
  bool get _isCareDurationValid => _isOrganisation || _careDuration != null;
  bool get _isToiletAssistanceValid => _isOrganisation || _toiletAssistance.isNotEmpty;
  bool get _isFeedingTypeValid => _isOrganisation || _feedingType != null;
  bool get _isSalaryValid => _isOrganisation || _salaryController.text.trim().isNotEmpty;

  // "None" reads/writes as _noneFeedingType/_noneToiletAssistance on the
  // dropdowns themselves (so the field's own selected-value matching stays
  // simple), but is never the value actually sent to deriveCareTier() or
  // the backend — both read through these getters instead of the raw
  // fields.
  String get _effectiveFeedingType =>
      _feedingType == _noneFeedingType ? FeedingType.oralFeeding : (_feedingType ?? FeedingType.oralFeeding);
  List<String> get _effectiveToiletAssistance => _toiletAssistance.contains(_noneToiletAssistance)
      ? const [ToiletAssistance.independent]
      : _toiletAssistance;

  /// Rebuilds a [CareReceiverModel] from whatever's currently selected on
  /// this form, for [deriveCareTier] — vitals aren't collected on this form
  /// at all, so they're just fixed at their server-side default.
  CareReceiverModel get _careReceiverForTierDerivation => CareReceiverModel(
        id: '',
        age: _age ?? 0,
        gender: _gender ?? '',
        weightKg: _weightKg ?? 0,
        feedingType: _effectiveFeedingType,
        hasMedicalCondition: !_medicalConditions.contains(_noneMedicalCondition),
        medicalConditions: _medicalConditions.contains(_noneMedicalCondition) ? const [] : _medicalConditions,
        toiletAssistance: _effectiveToiletAssistance,
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
    if (_salaryController.text.isEmpty || _salaryController.text == _lastAutoSuggestedSalary) {
      _salaryController.text = suggestion;
      _lastAutoSuggestedSalary = suggestion;
    }
  }

  /// Few Days/Few Weeks price off the daily Rate Card, Few Months/Long Term
  /// off the monthly one — see [frequencyForCareDuration].
  String? get _derivedFrequencyOfCare => _careDuration == null ? null : frequencyForCareDuration(_careDuration!);

  /// Purely advisory, never blocks submission — a male patient requesting
  /// a female caregiver is a much harder match to fill than any other
  /// combination, so we say so up front rather than letting the family
  /// find out only after posting.
  bool get _showGenderMismatchWarning => _gender == Gender.male && _preferredGender == Gender.female;

  /// Purely advisory, never blocks submission — many nurses decline
  /// short-term (few days/weeks) assignments, so the family is warned up
  /// front that they may get fewer or no applicants, with a suggestion to
  /// edit to a longer duration later if that happens.
  bool get _showShortTermDurationWarning =>
      _careDuration == CareDuration.fewDays || _careDuration == CareDuration.fewWeeks;

  bool get _canSubmit =>
      !_loading &&
      _isPhoneValid &&
      _isCodeValid &&
      _isFullNameValid &&
      _isOrganisationNameValid &&
      _isOrganisationTypeValid &&
      _isOrganisationCityValid &&
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
      _isSalaryValid &&
      _isTermsValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one seen when Register scrolls/focuses to it.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_phoneKey, _isPhoneValid, focusNode: _phoneFocusNode),
        _MandatoryField(_codeKey, _isCodeValid, focusNode: _codeFocusNode),
        if (_isOrganisation) ...[
          _MandatoryField(_fullNameKey, _isFullNameValid, focusNode: _fullNameFocusNode),
          _MandatoryField(_organisationNameKey, _isOrganisationNameValid, focusNode: _organisationNameFocusNode),
          _MandatoryField(_organisationTypeKey, _isOrganisationTypeValid),
          _MandatoryField(_organisationCityKey, _isOrganisationCityValid),
        ] else ...[
          _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
          _MandatoryField(_genderKey, _isGenderValid),
          _MandatoryField(_weightKey, _isWeightValid, focusNode: _weightFocusNode),
          _MandatoryField(_cityKey, _isCityValid),
          _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
          _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
          _MandatoryField(_startDateKey, _isStartDateValid),
          _MandatoryField(_careDurationKey, _isCareDurationValid),
          _MandatoryField(_toiletAssistanceKey, _isToiletAssistanceValid),
          _MandatoryField(_feedingTypeKey, _isFeedingTypeValid),
          _MandatoryField(_salaryKey, _isSalaryValid, focusNode: _salaryFocusNode),
        ],
        _MandatoryField(_termsKey, _isTermsValid),
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

  /// Register is always tappable — this is what runs when it's pressed.
  /// With something missing, it flags every missing mandatory field red and
  /// jumps straight to the first one instead of submitting.
  Future<void> _handleSubmitPressed() async {
    if (_loading) return;
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
          // to scroll means ensureVisible scrolls against the final,
          // keyboard-shrunk viewport size.
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
      _loading = true;
      _errorMessage = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final localStorage = ref.read(localStorageProvider);

      if (_isOrganisation) {
        final result = await authRepo.registerOrganisation(
          phone: _phone,
          code: _otpMode ? null : _codeController.text.trim(),
          phoneVerificationToken: _otpMode ? _verificationToken : null,
          organisationName: _organisationNameController.text.trim(),
          contactPersonName: _fullNameController.text.trim(),
          organisationType: _organisationType!,
          city: _organisationCity!,
          area: _organisationAreaController.text.trim().isEmpty ? null : _organisationAreaController.text.trim(),
          termsAccepted: _termsAccepted,
        );
        await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
        await ref.read(sessionProvider.notifier).loadSession();
      } else {
        // Register first — unless a prior submit already created the
        // account and only the requirement-posting step below failed, in
        // which case the session is already authenticated and this retries
        // just that step. Tapping "Post Requirement" again is the only
        // recovery path for that rare partial failure — there is no
        // separate "post a requirement" screen any more.
        final existingSession = ref.read(sessionProvider);
        if (existingSession is! SessionAuthenticated) {
          final result = await authRepo.register(
            phone: _phone,
            termsAccepted: _termsAccepted,
            code: _otpMode ? null : _codeController.text.trim(),
            phoneVerificationToken: _otpMode ? _verificationToken : null,
          );
          await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
          await ref.read(sessionProvider.notifier).loadSession();
        }
        await ref.read(individualRepositoryProvider).createRequirement(
              careReceiver: CareReceiverInput(
                age: _age!,
                gender: _gender!,
                weightKg: _weightKg!,
                feedingType: _effectiveFeedingType,
                hasMedicalCondition: !_medicalConditions.contains(_noneMedicalCondition),
                medicalConditions: _medicalConditions.contains(_noneMedicalCondition) ? null : _medicalConditions,
                medicalConditionOther: _medicalConditionOtherController.text.trim(),
                toiletAssistance: _effectiveToiletAssistance.isEmpty ? null : _effectiveToiletAssistance,
                toiletAssistanceOther: _toiletAssistanceOtherController.text.trim(),
              ),
              city: _city!,
              area: _areaController.text.trim(),
              dutyType: _dutyType!,
              startDate:
                  '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
              careDuration: _careDuration!,
              languages: _languages.contains(_noPreferenceLanguage) ? [] : _languages,
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
              frequencyOfCare: _derivedFrequencyOfCare!,
              salaryAmount: _salaryController.text.trim(),
            );
      }

      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session is SessionAuthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil(session.homeRoute, (route) => false);
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formContent = ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          _isOrganisation ? 'Hospital/Clinic/Rehab/Agency Registration Form' : "Patient/Patient's Family Registration Form",
          style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: _phoneKey,
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: '+91 ',
            labelText: 'Phone number (Mandatory)',
            border: const OutlineInputBorder(),
            errorText: _showValidationErrors && !_isPhoneValid ? 'Enter a valid 10-digit mobile number' : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_otpMode) _buildOtpVerificationBlock() else _buildPinField(),
        if (_isOrganisation) ..._buildOrganisationFields() else ..._buildIndividualFields(),
        const SizedBox(height: AppSpacing.lg),
        KeyedSubtree(
          key: _termsKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                key: const Key('termsCheckbox'),
                value: _termsAccepted,
                onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                title: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: _showValidationErrors && !_isTermsValid ? AppColors.error : AppColors.textPrimary,
                    ),
                    children: [
                      const TextSpan(text: 'I accept the '),
                      TextSpan(
                        text: 'Terms & Conditions',
                        style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()..onTap = _openTerms,
                      ),
                      const TextSpan(text: ' (mandatory)'),
                    ],
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_showValidationErrors && !_isTermsValid)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'You must accept the Terms & Conditions to continue',
                    style: TextStyle(color: AppColors.error, fontSize: AppTypography.small),
                  ),
                ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          onPressed: _loading ? null : _handleSubmitPressed,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isOrganisation ? 'Register' : 'Post Requirement'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const VitaAppBarTitle('Register'),
        actions: _isOrganisation ? const [WhatsAppHelpButton()] : const [RateCardButton(), WhatsAppHelpButton()],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isOrganisation
            ? formContent
            : Column(
                children: [
                  _buildSalaryBar(),
                  Expanded(child: formContent),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildOrganisationFields() => [
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: _fullNameKey,
          controller: _fullNameController,
          focusNode: _fullNameFocusNode,
          maxLength: Validation.nameMaxLength,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Contact person name (Mandatory)',
            border: const OutlineInputBorder(),
            errorText: _showValidationErrors && !_isFullNameValid ? 'Enter a name (letters and spaces only)' : null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Organisation Details', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: _organisationNameKey,
          controller: _organisationNameController,
          focusNode: _organisationNameFocusNode,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Organisation name (Mandatory)',
            border: const OutlineInputBorder(),
            errorText: _showValidationErrors && !_isOrganisationNameValid ? 'Organisation name is required' : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: _organisationTypeKey,
          isExpanded: true,
          initialValue: _organisationType,
          decoration: InputDecoration(
            labelText: 'Type of organisation (Mandatory)',
            border: const OutlineInputBorder(),
            errorText: _showValidationErrors && !_isOrganisationTypeValid ? 'Select a type of organisation' : null,
          ),
          items: OrganisationType.all
              .map((t) => DropdownMenuItem(value: t, child: Text(OrganisationType.displayNames[t] ?? t)))
              .toList(),
          onChanged: (value) => setState(() => _organisationType = value),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: _organisationCityKey,
          isExpanded: true,
          initialValue: _organisationCity,
          decoration: InputDecoration(
            labelText: 'City (Mandatory)',
            border: const OutlineInputBorder(),
            errorText: _showValidationErrors && !_isOrganisationCityValid ? 'Please select a city' : null,
          ),
          items: [
            ...City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))),
            const DropdownMenuItem(value: _organisationCityOthers, child: Text('Others')),
          ],
          onChanged: (value) => setState(() => _organisationCity = value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _organisationAreaController,
          decoration: const InputDecoration(
            labelText: 'Area (Optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ];

  List<Widget> _buildIndividualFields() => [
        const SizedBox(height: AppSpacing.lg),
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
                prefixIcon: const Icon(Icons.wc),
                labelText: "Patient's Gender (Mandatory)",
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isGenderValid ? 'Please select a gender' : null,
              ),
              items: Gender.all.map((g) => DropdownMenuItem(value: g, child: Text(_capitalize(g)))).toList(),
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
                errorText: _showValidationErrors && !_isWeightValid ? 'Weight is required (1-300 kg)' : null,
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
                prefixIcon: const Icon(Icons.location_on),
                labelText: 'Area (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isAreaValid ? 'Area is required' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            AreaCharLimitNote(currentLength: _areaController.text.length),
            const SizedBox(height: AppSpacing.md),
            const Row(
              children: [
                Icon(Icons.medical_information, size: 18, color: AppColors.primaryDark),
                SizedBox(width: AppSpacing.xs),
                Flexible(child: Text('Medical Condition (Mandatory)', style: SectionBox.fieldGroupLabelStyle)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: [_noneMedicalCondition, ...MedicalCondition.all],
              labels: {_noneMedicalCondition: _noneMedicalConditionLabel, ...MedicalCondition.displayNames},
              selected: _medicalConditions,
              onChanged: (next) => setState(() {
                _applyMedicalConditionSelection(next);
                _refreshSuggestedSalary();
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
                      errorText: _showValidationErrors && !_isDutyTypeValid ? 'Please select duty hours' : null,
                    ),
                    items: DutyType.all
                        .map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d)))
                        .toList(),
                    onChanged: (value) => setState(() => _dutyType = value),
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
                        color: _showValidationErrors && !_isStartDateValid ? AppColors.error : AppColors.primaryDark,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Preferred Start Date (Mandatory)',
                          style: SectionBox.fieldGroupLabelStyle.copyWith(
                            color: _showValidationErrors && !_isStartDateValid ? AppColors.error : null,
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
                          style: TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
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
                errorText: _showValidationErrors && !_isCareDurationValid ? 'Please select how long care is needed' : null,
              ),
              items: CareDuration.all
                  .map((d) => DropdownMenuItem(value: d, child: Text(CareDuration.displayNames[d] ?? d)))
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
                    Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Short-term requirement',
                            style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Many nurses do not accept short-term assignments. You can '
                            'continue with this requirement, but you may receive fewer '
                            "or no applicants. If you don't find a suitable nurse, you "
                            'may edit this job to "Need for minimum a month".',
                            style: TextStyle(color: AppColors.warning),
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
              initialValue: _toiletAssistance.isEmpty ? null : _toiletAssistance.first,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.wash),
                labelText: 'Toilet Assistance (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isToiletAssistanceValid ? 'Please select toilet assistance' : null,
              ),
              items: [
                const DropdownMenuItem(value: _noneToiletAssistance, child: Text(_noneToiletAssistanceLabel)),
                ...ToiletAssistance.all
                    .map((t) => DropdownMenuItem(value: t, child: Text(ToiletAssistance.displayNames[t] ?? t))),
              ],
              onChanged: (value) => setState(() {
                _toiletAssistance
                  ..clear()
                  ..add(value!);
                _refreshSuggestedSalary();
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
            DropdownButtonFormField<String>(
              key: _feedingTypeKey,
              isExpanded: true,
              initialValue: _feedingType,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.restaurant),
                labelText: 'Feeding/Medicine Assistance (Mandatory)',
                border: const OutlineInputBorder(),
                errorText:
                    _showValidationErrors && !_isFeedingTypeValid ? 'Please select feeding/medicine assistance' : null,
              ),
              items: [
                const DropdownMenuItem(value: _noneFeedingType, child: Text(_noneFeedingTypeLabel)),
                ...FeedingType.all.map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f))),
              ],
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
                  prefixIcon: Icon(Icons.people_outline), labelText: 'Preferred Caregiver Gender', border: OutlineInputBorder()),
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
          ],
        ),
      ];

  Widget _buildPinField() {
    return TextField(
      key: _codeKey,
      controller: _codeController,
      focusNode: _codeFocusNode,
      keyboardType: TextInputType.number,
      maxLength: 4,
      obscureText: true,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Create a 4-digit PIN (Mandatory)',
        border: const OutlineInputBorder(),
        errorText: _showValidationErrors && !_isCodeValid ? 'Enter a 4-digit PIN' : null,
      ),
    );
  }

  /// OTP-mode counterpart to _buildPinField — verifying the phone number
  /// (via a full send/verify round trip) is what satisfies this mandatory
  /// field instead of setting a PIN. Three states: not yet sent, sent
  /// (awaiting the code), and verified.
  Widget _buildOtpVerificationBlock() {
    return KeyedSubtree(
      key: _codeKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify Phone Number (Mandatory)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _showValidationErrors && !_isCodeValid ? AppColors.error : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_verificationToken != null)
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success),
                SizedBox(width: AppSpacing.sm),
                Flexible(child: Text('Phone number verified', overflow: TextOverflow.ellipsis)),
              ],
            )
          else if (!_otpSent)
            OutlinedButton(
              onPressed: _sendingOtp ? null : _sendRegistrationOtp,
              child: _sendingOtp
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send OTP to verify'),
            )
          else ...[
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6-digit OTP', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _verifyingOtp ? null : _verifyRegistrationOtp,
                  child: _verifyingOtp
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Verify'),
                ),
                TextButton(
                  onPressed: _sendingOtp ? null : _sendRegistrationOtp,
                  child: const Text('Resend OTP'),
                ),
              ],
            ),
          ],
          if (_showValidationErrors && !_isCodeValid)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Verify your phone number to continue', style: TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
            ),
        ],
      ),
    );
  }

  /// Sticky bar pinned below the AppBar (a sibling of the scrollable form,
  /// not inside it) so Salary stays visible no matter how far the
  /// (now much longer, registration+requirement) form is scrolled.
  /// Frequency of Care is derived internally (see _derivedFrequencyOfCare)
  /// purely to pick the ₹/day vs ₹/month unit and to submit
  /// frequency_of_care — it's never displayed on its own. Only shown for
  /// the Individual branch — Organisation has no salary concept.
  ///
  /// The Salary input itself only appears once Duration Care is Needed,
  /// Toilet Assistance, and Feeding/Medicine Assistance are all filled in —
  /// a placeholder hint fills the bar until then.
  Widget _buildSalaryBar() {
    final ready = _isCareDurationValid && _isToiletAssistanceValid && _isFeedingTypeValid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
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
              style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.small, fontWeight: FontWeight.w500),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This is just a guidance, you must discuss it directly '
                  'with caregivers. Fees are paid directly to the '
                  'Nurse/Caregivers.',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.caption, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  key: _salaryKey,
                  width: double.infinity,
                  child: TextField(
                    controller: _salaryController,
                    focusNode: _salaryFocusNode,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText:
                          'Salary (₹/${_derivedFrequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month'}) (Negotiable)',
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _showValidationErrors && !_isSalaryValid ? 'Salary is required' : null,
                    ),
                  ),
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
  /// [deriveCareTier] derives from the form's current selections.
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
        const Text('.', style: TextStyle(color: AppColors.textPrimary, fontSize: AppTypography.small)),
      ],
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
