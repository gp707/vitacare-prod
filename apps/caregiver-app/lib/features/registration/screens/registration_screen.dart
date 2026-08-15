import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
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
  String? _religion;
  final List<String> _preferredCities = [];
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
    if (_religion == null) {
      setState(() => _errorMessage = 'Select your religion');
      return;
    }
    if (_qualification == null) {
      setState(() => _errorMessage = 'Select your highest qualification');
      return;
    }
    if (_selfieBytes == null) {
      setState(() => _errorMessage = 'Take a selfie to continue');
      return;
    }
    if (_aadhaarBytes == null) {
      setState(() => _errorMessage = 'Upload your Aadhaar card to continue');
      return;
    }
    if (!_termsAccepted) {
      setState(() => _errorMessage = 'You must accept the Terms & Conditions to continue');
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
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _religion,
              decoration: const InputDecoration(labelText: 'Religion', border: OutlineInputBorder()),
              items: Religion.all
                  .map((r) => DropdownMenuItem(value: r, child: Text(Religion.displayNames[r] ?? r)))
                  .toList(),
              onChanged: (value) => setState(() => _religion = value),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Preferred City (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: City.all,
              labels: City.displayNames,
              selected: _preferredCities,
              onChanged: (next) => setState(() {
                _preferredCities
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _qualification,
              decoration: const InputDecoration(
                labelText: 'Highest Qualification',
                border: OutlineInputBorder(),
              ),
              items: Qualification.all
                  .map((q) => DropdownMenuItem(value: q, child: Text(Qualification.displayNames[q] ?? q)))
                  .toList(),
              onChanged: (value) => setState(() => _qualification = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _takeSelfie,
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
            const SizedBox(height: AppSpacing.sm),
            _DocumentPicker(
              label: 'Aadhaar Card (mandatory)',
              filename: _aadhaarFilename,
              onTap: _pickAadhaar,
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
            CheckboxListTile(
              value: _termsAccepted,
              onChanged: (value) => setState(() => _termsAccepted = value ?? false),
              title: const Text('I accept the Terms & Conditions (mandatory)'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
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

class _DocumentPicker extends StatelessWidget {
  final String label;
  final String? filename;
  final VoidCallback? onTap;

  const _DocumentPicker({required this.label, required this.filename, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
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
