import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../profile/data/profile_repository.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _codeController = TextEditingController();
  String _gender = Gender.female;
  final List<String> _languages = [];
  Uint8List? _selfieBytes;
  String? _selfieFilename;
  bool _loading = false;
  String? _errorMessage;

  String get _phone => '+91${_phoneController.text.trim()}';

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _codeController.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    final name = _fullNameController.text.trim();
    final ageText = _ageController.text.trim();
    final age = int.tryParse(ageText);

    if (!Validators.isValidName(name)) {
      setState(() => _errorMessage = 'Enter a valid full name (letters and spaces only)');
      return;
    }
    if (!Validators.isValidPhone(_phone)) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }
    if (age == null || !Validators.isValidAge(age)) {
      setState(() => _errorMessage = 'Age must be between ${Validation.ageMin} and ${Validation.ageMax}');
      return;
    }
    if (_languages.isEmpty) {
      setState(() => _errorMessage = 'Select at least one language');
      return;
    }
    if (!Validators.isValidCode(_codeController.text.trim())) {
      setState(() => _errorMessage = 'Set a 4-digit code — you\'ll use it with your phone to log in');
      return;
    }
    if (_selfieBytes == null) {
      setState(() => _errorMessage = 'Take a selfie to continue');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final result = await authRepo.register(
        phone: _phone,
        fullName: name,
        gender: _gender,
        age: age,
        languages: _languages,
        code: _codeController.text.trim(),
      );

      final localStorage = ref.read(localStorageProvider);
      await localStorage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
      unawaited(ref.read(fcmServiceProvider).register());

      final ProfileRepository profileRepo = ref.read(profileRepositoryProvider);
      await profileRepo.uploadSelfie(_selfieBytes!, _selfieFilename ?? 'selfie.jpg');

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
      appBar: AppBar(title: const Text('Register')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _SalaryRangesCard(),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                prefixText: '+91 ',
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
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
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Languages', style: TextStyle(fontWeight: FontWeight.w600)),
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
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '4-Digit Login Code',
                helperText: "You'll use this + your phone number to log in from now on",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _takeSelfie,
              icon: const Icon(Icons.camera_alt),
              label: Text(_selfieBytes == null ? 'Take Selfie' : 'Retake Selfie'),
            ),
            if (_selfieBytes != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                child: Image.memory(_selfieBytes!, height: 120, width: 120, fit: BoxFit.cover),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
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

class _SalaryRangesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly salary ranges', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Companion Care: ₹${SalaryRanges.companionCare.min} – ₹${SalaryRanges.companionCare.max}',
          ),
          Text(
            'Bedside Care: ₹${SalaryRanges.bedsideCare.min} – ₹${SalaryRanges.bedsideCare.max}',
          ),
          Text(
            'Critical Care: ₹${SalaryRanges.criticalCare.min} – ₹${SalaryRanges.criticalCare.max}',
          ),
        ],
      ),
    );
  }
}
