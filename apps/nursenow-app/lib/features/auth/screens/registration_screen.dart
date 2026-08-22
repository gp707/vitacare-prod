import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_result.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';

enum _AccountType { individual, organisation }

// organisation_profiles.city accepts the existing 7 cities plus this one
// extra sentinel — a separate org-scoped list, not an extension of the
// shared City enum (see "NurseNow" in CLAUDE.md).
const _organisationCityOthers = 'others';

// Each account type has its own Terms & Conditions document (an org's
// legal terms differ from an individual/family's) — the checkbox links out
// to whichever one matches the currently-selected account type.
const _individualTermsUrl =
    'https://docs.google.com/document/d/1TvqDSP5EZRh8ZtxLhRH_b46J7Q-6cIV5VCUsTkH1Q5s/edit?tab=t.0';
const _organisationTermsUrl =
    'https://docs.google.com/document/d/1y_o29xiumKqmzshox58vGcYYFnWVUKWL6cd6m_Eycpw/edit?tab=t.0';

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Flow: phone -> PIN -> name -> account type -> (Individual: done;
/// Organisation: org name/type/city/area, shown once selected — the
/// "name" field above doubles as contact person name for an org).
///
/// Submit is always tappable (mirrors admin-web's job-posting form and
/// nursenow-app's own PostRequirementScreen): if a mandatory field is
/// missing, tapping it flags every missing mandatory field red and
/// scrolls/focuses straight to the first one instead of submitting.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _organisationNameController = TextEditingController();
  final _areaController = TextEditingController();
  _AccountType? _accountType;
  String? _organisationType;
  String? _city;
  bool _termsAccepted = false;
  bool _loading = false;
  String? _errorMessage;

  final _phoneFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();
  final _fullNameFocusNode = FocusNode();
  final _organisationNameFocusNode = FocusNode();
  final _areaFocusNode = FocusNode();

  final _phoneKey = GlobalKey();
  final _codeKey = GlobalKey();
  final _fullNameKey = GlobalKey();
  final _accountTypeKey = GlobalKey();
  final _organisationNameKey = GlobalKey();
  final _organisationTypeKey = GlobalKey();
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _termsKey = GlobalKey();

  // Only turns true once Register has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  bool get _isOrganisation => _accountType == _AccountType.organisation;

  String get _phone => '+91${_phoneController.text.trim()}';

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _fullNameController.dispose();
    _organisationNameController.dispose();
    _areaController.dispose();
    _phoneFocusNode.dispose();
    _codeFocusNode.dispose();
    _fullNameFocusNode.dispose();
    _organisationNameFocusNode.dispose();
    _areaFocusNode.dispose();
    super.dispose();
  }

  bool get _isPhoneValid => Validators.isValidPhone(_phone);
  bool get _isCodeValid => Validators.isValidCode(_codeController.text.trim());
  bool get _isFullNameValid => Validators.isValidName(_fullNameController.text.trim());
  bool get _isAccountTypeValid => _accountType != null;
  bool get _isOrganisationNameValid => !_isOrganisation || _organisationNameController.text.trim().isNotEmpty;
  bool get _isOrganisationTypeValid => !_isOrganisation || _organisationType != null;
  bool get _isCityValid => !_isOrganisation || _city != null;
  bool get _isAreaValid => !_isOrganisation || _areaController.text.trim().isNotEmpty;
  bool get _isTermsValid => _termsAccepted;

  String get _termsUrl => _isOrganisation ? _organisationTermsUrl : _individualTermsUrl;

  Future<void> _openTerms() => launchUrl(Uri.parse(_termsUrl), mode: LaunchMode.externalApplication);

  bool get _canSubmit =>
      !_loading &&
      _isPhoneValid &&
      _isCodeValid &&
      _isFullNameValid &&
      _isAccountTypeValid &&
      _isOrganisationNameValid &&
      _isOrganisationTypeValid &&
      _isCityValid &&
      _isAreaValid &&
      _isTermsValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one seen when Register scrolls/focuses to it.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_phoneKey, _isPhoneValid, focusNode: _phoneFocusNode),
        _MandatoryField(_codeKey, _isCodeValid, focusNode: _codeFocusNode),
        _MandatoryField(_fullNameKey, _isFullNameValid, focusNode: _fullNameFocusNode),
        _MandatoryField(_accountTypeKey, _isAccountTypeValid),
        if (_isOrganisation) ...[
          _MandatoryField(_organisationNameKey, _isOrganisationNameValid, focusNode: _organisationNameFocusNode),
          _MandatoryField(_organisationTypeKey, _isOrganisationTypeValid),
          _MandatoryField(_cityKey, _isCityValid),
          _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        ],
        _MandatoryField(_termsKey, _isTermsValid),
      ];

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
      _loading = true;
      _errorMessage = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final AuthResult result = _isOrganisation
          ? await authRepo.registerOrganisation(
              phone: _phone,
              code: _codeController.text.trim(),
              organisationName: _organisationNameController.text.trim(),
              contactPersonName: _fullNameController.text.trim(),
              organisationType: _organisationType!,
              city: _city!,
              area: _areaController.text.trim(),
              termsAccepted: _termsAccepted,
            )
          : await authRepo.register(
              phone: _phone,
              fullName: _fullNameController.text.trim(),
              termsAccepted: _termsAccepted,
              code: _codeController.text.trim(),
            );
      final localStorage = ref.read(localStorageProvider);
      await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
      await ref.read(sessionProvider.notifier).loadSession();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
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
            TextField(
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
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: _fullNameKey,
              controller: _fullNameController,
              focusNode: _fullNameFocusNode,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isOrganisation ? 'Contact person name (Mandatory)' : 'Full name (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isFullNameValid
                    ? 'Enter a name (letters and spaces only)'
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            KeyedSubtree(
              key: _accountTypeKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account type (Mandatory)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _showValidationErrors && !_isAccountTypeValid ? AppColors.error : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  RadioListTile<_AccountType>(
                    title: const Text('Individual'),
                    subtitle: const Text('Patient, or a family member/caregiver acting on their behalf'),
                    value: _AccountType.individual,
                    groupValue: _accountType,
                    onChanged: (value) => setState(() => _accountType = value),
                  ),
                  RadioListTile<_AccountType>(
                    title: const Text('Hospital / Rehab'),
                    subtitle: const Text('Post care requirements on behalf of your organisation'),
                    value: _AccountType.organisation,
                    groupValue: _accountType,
                    onChanged: (value) => setState(() => _accountType = value),
                  ),
                  if (_showValidationErrors && !_isAccountTypeValid)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 12),
                      child: Text('Select an account type', style: TextStyle(color: AppColors.error, fontSize: 12)),
                    ),
                ],
              ),
            ),
            if (_isOrganisation) ...[
              const SizedBox(height: AppSpacing.lg),
              const Text('Organisation Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: _organisationNameKey,
                controller: _organisationNameController,
                focusNode: _organisationNameFocusNode,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Organisation name (Mandatory)',
                  border: const OutlineInputBorder(),
                  errorText: _showValidationErrors && !_isOrganisationNameValid
                      ? 'Organisation name is required'
                      : null,
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
                  errorText:
                      _showValidationErrors && !_isOrganisationTypeValid ? 'Select a type of organisation' : null,
                ),
                items: OrganisationType.all
                    .map((t) => DropdownMenuItem(value: t, child: Text(OrganisationType.displayNames[t] ?? t)))
                    .toList(),
                onChanged: (value) => setState(() => _organisationType = value),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: _cityKey,
                isExpanded: true,
                initialValue: _city,
                decoration: InputDecoration(
                  labelText: 'City (Mandatory)',
                  border: const OutlineInputBorder(),
                  errorText: _showValidationErrors && !_isCityValid ? 'Please select a city' : null,
                ),
                items: [
                  ...City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))),
                  const DropdownMenuItem(value: _organisationCityOthers, child: Text('Others')),
                ],
                onChanged: (value) => setState(() => _city = value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: _areaKey,
                controller: _areaController,
                focusNode: _areaFocusNode,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Area (Mandatory)',
                  border: const OutlineInputBorder(),
                  errorText: _showValidationErrors && !_isAreaValid ? 'Area is required' : null,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            KeyedSubtree(
              key: _termsKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    value: _termsAccepted,
                    onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                    title: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 14,
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
                        style: TextStyle(color: AppColors.error, fontSize: 12),
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
                  : const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}
