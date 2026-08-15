import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';

const _reReviewStatuses = [
  VerificationStatus.available,
  VerificationStatus.unavailable,
  VerificationStatus.rejected,
];

/// Single self-edit screen covering every caregiver-editable field — there's
/// no more "Basic" vs "Advanced" split now that everything is collected in
/// one registration. full_name, gender, and religion are read-only here —
/// only admins can change them once set at registration. Phone and PIN are
/// independently-saved sections since they map to different backend
/// endpoints with different review-trigger semantics (phone can send an
/// available/unavailable/rejected caregiver back for re-review; PIN never
/// does). Editing anything here while rejected auto-resubmits (server-side)
/// — no separate "resubmit" action needed.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;

  final _ageController = TextEditingController();
  final List<String> _languages = [];
  String? _qualification;
  List<String> _preferredCities = [];
  bool _savingProfile = false;
  String? _profileError;
  String? _profileSuccess;

  final _phoneController = TextEditingController();
  bool _savingPhone = false;
  String? _phoneError;
  String? _phoneSuccess;

  final _codeController = TextEditingController();
  bool _savingCode = false;
  String? _codeError;
  String? _codeSuccess;

  final Set<String> _uploadingDocType = {};
  String? _docError;
  String? _docSuccess;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ref.read(profileRepositoryProvider).getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _ageController.text = '${profile.age}';
      _languages
        ..clear()
        ..addAll(profile.languages);
      _qualification = profile.highestQualification;
      _preferredCities = List.from(profile.preferredCities);
      _phoneController.text = profile.phone.replaceFirst('+91', '');
      _loading = false;
    });
  }

  bool get _willTriggerReview =>
      _profile != null && _reReviewStatuses.contains(_profile!.verificationStatus);

  bool _preferredCitiesChanged(CaregiverProfileModel profile) {
    final next = [..._preferredCities]..sort();
    final previous = [...profile.preferredCities]..sort();
    return next.join(',') != previous.join(',');
  }

  Future<void> _saveProfile() async {
    final profile = _profile!;
    setState(() {
      _savingProfile = true;
      _profileError = null;
      _profileSuccess = null;
    });
    try {
      final age = int.tryParse(_ageController.text.trim());
      if (age == null || !Validators.isValidAge(age)) {
        setState(() => _profileError = 'Age must be between ${Validation.ageMin} and ${Validation.ageMax}');
        return;
      }
      if (_languages.isEmpty) {
        setState(() => _profileError = 'Select at least one language');
        return;
      }
      final sortedNewLangs = [..._languages]..sort();
      final sortedOldLangs = [...profile.languages]..sort();
      final status = await ref.read(profileRepositoryProvider).editProfile(
            age: age != profile.age ? age : null,
            languages: sortedNewLangs.join(',') != sortedOldLangs.join(',') ? _languages : null,
            highestQualification:
                _qualification != profile.highestQualification ? _qualification : null,
            preferredCities: _preferredCitiesChanged(profile) ? _preferredCities : null,
          );
      setState(() {
        _profileSuccess = status == VerificationStatus.pendingCall && profile.verificationStatus == VerificationStatus.rejected
            ? 'Saved. Your profile has been resubmitted for review.'
            : 'Saved. Your admin will see this change flagged for review.';
      });
      await _load();
    } on ApiException catch (e) {
      setState(() => _profileError = e.message);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePhone() async {
    final phone = '+91${_phoneController.text.trim()}';
    if (!Validators.isValidPhone(phone)) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() {
      _savingPhone = true;
      _phoneError = null;
      _phoneSuccess = null;
    });
    try {
      final wasReReviewed = _willTriggerReview;
      await ref.read(profileRepositoryProvider).updatePhone(phone);
      await ref.read(sessionProvider.notifier).refreshStatus();
      setState(() {
        _phoneSuccess = wasReReviewed
            ? 'Phone updated. Your profile has been sent back for re-review.'
            : 'Phone updated.';
      });
      await _load();
    } on ApiException catch (e) {
      setState(() => _phoneError = e.message);
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  Future<void> _saveCode() async {
    final code = _codeController.text.trim();
    if (!Validators.isValidCode(code)) {
      setState(() => _codeError = 'Code must be exactly 4 digits');
      return;
    }
    setState(() {
      _savingCode = true;
      _codeError = null;
      _codeSuccess = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateCode(code);
      setState(() {
        _codeSuccess = 'Login code updated.';
        _codeController.clear();
      });
    } on ApiException catch (e) {
      setState(() => _codeError = e.message);
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  Future<void> _pickAndUploadSelfie() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null) return;
    setState(() {
      _uploadingDocType.add('selfie');
      _docError = null;
      _docSuccess = null;
    });
    try {
      final bytes = await photo.readAsBytes();
      await ref.read(profileRepositoryProvider).uploadSelfie(bytes, photo.name);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _docError = e.message);
    } finally {
      if (mounted) setState(() => _uploadingDocType.remove('selfie'));
    }
  }

  Future<void> _pickAndUploadDocument(String documentType) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    setState(() {
      _uploadingDocType.add(documentType);
      _docError = null;
      _docSuccess = null;
    });
    try {
      final wasReReviewed = documentType == DocumentType.aadhaar && _willTriggerReview;
      await ref.read(profileRepositoryProvider).uploadDocument(picked.bytes!, picked.name, documentType);
      await ref.read(sessionProvider.notifier).refreshStatus();
      await _load();
      if (wasReReviewed && mounted) {
        setState(() => _docSuccess = 'Aadhaar updated. Your profile has been sent back for re-review.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _docError = e.message);
    } finally {
      if (mounted) setState(() => _uploadingDocType.remove(documentType));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                    child: const Text(
                      "Changes here will be reviewed by admin. Your current verification status is not affected — except changing your phone number or Aadhaar card, which sends an available/unavailable profile back for re-review (a rejected profile is always resubmitted by any change here).",
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_profile?.fullName ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                  const Text(
                    "Contact the office to change your name.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _profile != null
                        ? _profile!.gender[0].toUpperCase() + _profile!.gender.substring(1)
                        : '',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const Text(
                    "Contact the office to change your gender.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Religion', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    Religion.displayNames[_profile?.religion] ?? _profile?.religion ?? '',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const Text(
                    "Contact the office to change your religion.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Profile Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
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
                    initialValue: _qualification,
                    decoration:
                        const InputDecoration(labelText: 'Highest Qualification', border: OutlineInputBorder()),
                    items: Qualification.all
                        .map((q) => DropdownMenuItem(value: q, child: Text(Qualification.displayNames[q] ?? q)))
                        .toList(),
                    onChanged: (value) => setState(() => _qualification = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Preferred City (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  VitaMultiSelectChips(
                    options: City.all,
                    labels: City.displayNames,
                    selected: _preferredCities,
                    onChanged: (next) => setState(() => _preferredCities = next),
                  ),
                  if (_profileError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_profileError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_profileSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_profileSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _savingProfile ? null : _saveProfile,
                    child: _savingProfile ? const _ButtonSpinner() : const Text('Save'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Phone Number', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  if (_willTriggerReview)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                      ),
                      child: const Text(
                        'Changing your phone number will send your profile back for re-review.',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      prefixText: '+91 ',
                      labelText: 'Phone number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_phoneError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_phoneError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_phoneSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_phoneSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _savingPhone ? null : _savePhone,
                    child: _savingPhone ? const _ButtonSpinner() : const Text('Save Phone Number'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Login PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    "Changing your PIN never affects your verification status.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New 4-Digit PIN', border: OutlineInputBorder()),
                  ),
                  if (_codeError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_codeError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_codeSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_codeSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: _savingCode ? null : _saveCode,
                    child: _savingCode ? const _ButtonSpinner() : const Text('Save PIN'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  _DocumentSlot(
                    title: 'Selfie (mandatory)',
                    uploaded: _profile?.selfiePhotoUrl != null,
                    isUploading: _uploadingDocType.contains('selfie'),
                    onTap: _pickAndUploadSelfie,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DocumentSlot(
                    title: 'Aadhaar Card (mandatory)',
                    uploaded: _profile?.aadhaarDocumentUrl != null,
                    isUploading: _uploadingDocType.contains(DocumentType.aadhaar),
                    onTap: () => _pickAndUploadDocument(DocumentType.aadhaar),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DocumentSlot(
                    title: 'Qualification Document (optional)',
                    uploaded: _profile?.qualificationDocumentUrl != null,
                    isUploading: _uploadingDocType.contains(DocumentType.qualification),
                    onTap: () => _pickAndUploadDocument(DocumentType.qualification),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (int i = 0; i < Validation.maxOtherDocuments; i++) ...[
                    _DocumentSlot(
                      title: 'Other document ${i + 1}',
                      uploaded: i < (_profile?.otherDocumentUrls.length ?? 0),
                      isUploading: _uploadingDocType.contains(DocumentType.other) &&
                          i == (_profile?.otherDocumentUrls.length ?? 0),
                      onTap: i <= (_profile?.otherDocumentUrls.length ?? 0)
                          ? () => _pickAndUploadDocument(DocumentType.other)
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (_docError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_docError!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_docSuccess != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_docSuccess!, style: const TextStyle(color: AppColors.success)),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

class _DocumentSlot extends StatelessWidget {
  final String title;
  final bool uploaded;
  final bool isUploading;
  final VoidCallback? onTap;

  const _DocumentSlot({
    required this.title,
    required this.uploaded,
    required this.isUploading,
    required this.onTap,
  });

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
            uploaded ? Icons.check_circle : Icons.insert_drive_file_outlined,
            color: uploaded ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title)),
          if (isUploading)
            const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
          else
            TextButton(
              onPressed: onTap,
              child: Text(uploaded ? 'Replace' : 'Upload'),
            ),
        ],
      ),
    );
  }
}
