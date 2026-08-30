import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../app/rate_card_button.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../profile/data/profile_repository.dart';

const _termsUrl = 'https://docs.google.com/document/d/17BQ8hGoZ-U6Tqio-5pNsTZaDtQTlnl0XjJtmET0sG_Q/edit?tab=t.0';

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Submit is always tappable (mirrors admin-web's job-posting form and
/// nursenow-app's own RegistrationScreen): if a mandatory field is
/// missing, tapping Register flags every missing mandatory field red and
/// scrolls/focuses straight to the first one instead of submitting.
class RegistrationScreen extends ConsumerStatefulWidget {
  /// Injectable for widget tests — defaults to the real url_launcher call.
  final Future<bool> Function(Uri uri)? launcher;

  const RegistrationScreen({super.key, this.launcher});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _codeController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _verificationToken;
  String _gender = Gender.female;
  final List<String> _languages = [];
  String? _religion;
  // Read-only, fixed to every city — see the Preferred City section below.
  final List<String> _preferredCities = List<String>.from(City.all);
  String? _qualification;
  bool _termsAccepted = false;
  Uint8List? _selfieBytes;
  String? _selfieFilename;
  Uint8List? _aadhaarBytes;
  String? _aadhaarFilename;
  Uint8List? _qualificationDocBytes;
  String? _qualificationDocFilename;
  final List<PlatformFile> _otherDocs = [];
  bool _loading = false;
  String? _errorMessage;

  final _fullNameFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();
  final _ageFocusNode = FocusNode();

  final _fullNameKey = GlobalKey();
  final _phoneKey = GlobalKey();
  final _codeKey = GlobalKey();
  final _ageKey = GlobalKey();
  final _languagesKey = GlobalKey();
  final _religionKey = GlobalKey();
  final _qualificationKey = GlobalKey();
  final _selfieKey = GlobalKey();
  final _aadhaarKey = GlobalKey();
  final _termsKey = GlobalKey();

  // Only turns true once Register has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  String get _phone => '+91${_phoneController.text.trim()}';
  int? get _age => int.tryParse(_ageController.text.trim());
  bool get _otpMode => ref.read(otpModeProvider);

  bool get _isFullNameValid => Validators.isValidName(_fullNameController.text.trim());
  bool get _isPhoneValid => Validators.isValidPhone(_phone);
  bool get _isCodeValid => _otpMode ? _verificationToken != null : Validators.isValidCode(_codeController.text.trim());
  bool get _isAgeValid => _age != null && Validators.isValidAge(_age!);
  bool get _isLanguagesValid => _languages.isNotEmpty;
  bool get _isReligionValid => _religion != null;
  bool get _isQualificationValid => _qualification != null;
  bool get _isSelfieValid => _selfieBytes != null;
  bool get _isAadhaarValid => _aadhaarBytes != null;
  bool get _isTermsValid => _termsAccepted;

  bool get _canSubmit =>
      !_loading &&
      _isFullNameValid &&
      _isPhoneValid &&
      _isCodeValid &&
      _isAgeValid &&
      _isLanguagesValid &&
      _isReligionValid &&
      _isQualificationValid &&
      _isSelfieValid &&
      _isAadhaarValid &&
      _isTermsValid;

  /// In on-form order, so the first invalid one found here is genuinely the
  /// first one seen when Register scrolls/focuses to it.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_fullNameKey, _isFullNameValid, focusNode: _fullNameFocusNode),
        _MandatoryField(_phoneKey, _isPhoneValid, focusNode: _phoneFocusNode),
        _MandatoryField(_codeKey, _isCodeValid, focusNode: _codeFocusNode),
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_languagesKey, _isLanguagesValid),
        _MandatoryField(_religionKey, _isReligionValid),
        _MandatoryField(_qualificationKey, _isQualificationValid),
        _MandatoryField(_selfieKey, _isSelfieValid),
        _MandatoryField(_aadhaarKey, _isAadhaarValid),
        _MandatoryField(_termsKey, _isTermsValid),
      ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _codeController.dispose();
    _otpController.dispose();
    _fullNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _codeFocusNode.dispose();
    _ageFocusNode.dispose();
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

  Future<void> _takeSelfie() async {
    final picker = ImagePicker();
    // Camera capture only — CLAUDE.md: never offer ImageSource.gallery for the selfie.
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo != null) {
      // Image.file doesn't work on Flutter Web (no dart:io filesystem access
      // in the browser) — read bytes once, used for both the Image.memory
      // preview and the actual upload (ProfileRepository.uploadSelfie takes
      // bytes too, for the same reason).
      final bytes = await photo.readAsBytes();
      setState(() {
        _selfieBytes = bytes;
        _selfieFilename = photo.name;
      });
    }
  }

  Future<void> _pickAadhaar() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;
    setState(() {
      _aadhaarBytes = picked.bytes;
      _aadhaarFilename = picked.name;
    });
  }

  Future<void> _pickQualificationDoc() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;
    setState(() {
      _qualificationDocBytes = picked.bytes;
      _qualificationDocFilename = picked.name;
    });
  }

  Future<void> _pickOtherDoc() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;
    setState(() => _otherDocs.add(picked));
  }

  Future<void> _openTerms() async {
    final uri = Uri.parse(_termsUrl);
    final launcher = widget.launcher;
    if (launcher != null) {
      await launcher(uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      final result = await authRepo.register(
        phone: _phone,
        fullName: _fullNameController.text.trim(),
        gender: _gender,
        age: _age!,
        languages: _languages,
        code: _otpMode ? null : _codeController.text.trim(),
        phoneVerificationToken: _otpMode ? _verificationToken : null,
        religion: _religion!,
        preferredCities: _preferredCities.isEmpty ? null : _preferredCities,
        highestQualification: _qualification!,
        termsAccepted: _termsAccepted,
      );

      final localStorage = ref.read(localStorageProvider);
      await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
      unawaited(ref.read(fcmServiceProvider).register());

      final ProfileRepository profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.uploadSelfie(_selfieBytes!, _selfieFilename ?? 'selfie.jpg');
      await profileRepo.uploadDocument(_aadhaarBytes!, _aadhaarFilename ?? 'aadhaar', DocumentType.aadhaar);
      if (_qualificationDocBytes != null) {
        await profileRepo.uploadDocument(
          _qualificationDocBytes!,
          _qualificationDocFilename ?? 'qualification',
          DocumentType.qualification,
        );
      }
      for (final doc in _otherDocs) {
        await profileRepo.uploadDocument(doc.bytes!, doc.name, DocumentType.other);
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Registration Successful'),
          content: const Text(
            'You are successfully registered - you would receive a call from the office within 24Hrs.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/pending-call', (route) => false);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        actions: const [RateCardButton()],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextField(
              key: _fullNameKey,
              controller: _fullNameController,
              focusNode: _fullNameFocusNode,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Full Name (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isFullNameValid
                    ? 'Enter a valid full name (letters and spaces only)'
                    : null,
              ),
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
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
              items: Gender.all
                  .map((g) => DropdownMenuItem(value: g, child: Text(g[0].toUpperCase() + g.substring(1))))
                  .toList(),
              onChanged: (value) => setState(() => _gender = value ?? _gender),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: _ageKey,
              controller: _ageController,
              focusNode: _ageFocusNode,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Age (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isAgeValid
                    ? 'Age must be between ${Validation.ageMin} and ${Validation.ageMax}'
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            KeyedSubtree(
              key: _languagesKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Languages (Mandatory)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _showValidationErrors && !_isLanguagesValid ? AppColors.error : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
              key: _religionKey,
              isExpanded: true,
              initialValue: _religion,
              decoration: InputDecoration(
                labelText: 'Religion (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isReligionValid ? 'Select your religion' : null,
              ),
              items: Religion.all
                  .map((r) => DropdownMenuItem(value: r, child: Text(Religion.displayNames[r] ?? r)))
                  .toList(),
              onChanged: (value) => setState(() => _religion = value),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Preferred City', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            const Text(
              "You're shown jobs in every city for now — this can't be narrowed at registration.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: City.all
                  .map((city) => FilterChip(
                        label: Text(City.displayNames[city] ?? city),
                        selected: true,
                        onSelected: null,
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: _qualificationKey,
              isExpanded: true,
              initialValue: _qualification,
              decoration: InputDecoration(
                labelText: 'Highest Qualification (Mandatory)',
                border: const OutlineInputBorder(),
                errorText: _showValidationErrors && !_isQualificationValid ? 'Select your highest qualification' : null,
              ),
              items: Qualification.all
                  .map((q) => DropdownMenuItem(value: q, child: Text(Qualification.displayNames[q] ?? q)))
                  .toList(),
              onChanged: (value) => setState(() => _qualification = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            KeyedSubtree(
              key: _selfieKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _takeSelfie,
                    style: _showValidationErrors && !_isSelfieValid
                        ? OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error))
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_selfieBytes == null ? 'Take Selfie (mandatory)' : 'Retake Selfie'),
                  ),
                  if (_selfieBytes != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      child: Image.memory(_selfieBytes!, height: 120, width: 120, fit: BoxFit.cover),
                    ),
                  ],
                  if (_showValidationErrors && !_isSelfieValid)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Take a selfie to continue', style: TextStyle(color: AppColors.error, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentPicker(
              key: _aadhaarKey,
              label: 'Aadhaar Card (mandatory)',
              filename: _aadhaarFilename,
              onTap: _pickAadhaar,
              hasError: _showValidationErrors && !_isAadhaarValid,
              errorText: 'Upload your Aadhaar card to continue',
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentPicker(
              label: 'Qualification Document (optional)',
              filename: _qualificationDocFilename,
              onTap: _pickQualificationDoc,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Other Documents (optional, up to ${Validation.maxOtherDocuments})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < _otherDocs.length; i++) ...[
              _DocumentPicker(label: 'Other document ${i + 1}', filename: _otherDocs[i].name, onTap: null),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_otherDocs.length < Validation.maxOtherDocuments)
              OutlinedButton.icon(
                onPressed: _pickOtherDoc,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Other Document'),
              ),
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
              const SizedBox(height: AppSpacing.md),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
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
        labelText: '4-Digit Login Code (Mandatory)',
        helperText: "You'll use this + your phone number to log in from now on",
        border: const OutlineInputBorder(),
        errorText: _showValidationErrors && !_isCodeValid
            ? "Set a 4-digit code — you'll use it with your phone to log in"
            : null,
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
            Row(
              children: const [
                Icon(Icons.check_circle, color: AppColors.success),
                SizedBox(width: AppSpacing.sm),
                Text('Phone number verified'),
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
            Row(
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
                const SizedBox(width: AppSpacing.sm),
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
              child: Text('Verify your phone number to continue', style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _DocumentPicker extends StatelessWidget {
  final String label;
  final String? filename;
  final VoidCallback? onTap;
  final bool hasError;
  final String? errorText;

  const _DocumentPicker({
    super.key,
    required this.label,
    required this.filename,
    required this.onTap,
    this.hasError = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: hasError ? AppColors.error : AppColors.border, width: hasError ? 2 : 1),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Row(
            children: [
              Icon(
                filename != null ? Icons.check_circle : Icons.insert_drive_file_outlined,
                color: filename != null ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(filename ?? label)),
              if (onTap != null)
                TextButton(onPressed: onTap, child: Text(filename == null ? 'Upload' : 'Replace')),
            ],
          ),
        ),
        if (hasError && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(errorText!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ),
      ],
    );
  }
}
