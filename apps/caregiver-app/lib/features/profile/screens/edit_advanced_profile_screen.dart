import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';

const _reReviewStatuses = [VerificationStatus.available, VerificationStatus.unavailable];

/// Self-edit of the advanced/professional fields any time after the initial
/// submission (advanced_details_completed must already be true — enforced
/// server-side too). Only changed fields are sent (partial PATCH). Document
/// re-uploads live here too: selfie/qualification/other never trigger
/// review, but re-uploading Aadhaar does when the caregiver is currently
/// available/unavailable (per CLAUDE.md's transition matrix).
class EditAdvancedProfileScreen extends ConsumerStatefulWidget {
  const EditAdvancedProfileScreen({super.key});

  @override
  ConsumerState<EditAdvancedProfileScreen> createState() => _EditAdvancedProfileScreenState();
}

class _EditAdvancedProfileScreenState extends ConsumerState<EditAdvancedProfileScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;
  String? _qualification;
  List<String> _preferredCities = [];

  bool _saving = false;
  String? _errorMessage;
  String? _successMessage;
  final Set<String> _uploadingDocType = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ref.read(profileRepositoryProvider).getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _qualification = profile.highestQualification;
      _preferredCities = List.from(profile.preferredCities);
      _loading = false;
    });
  }

  bool get _willTriggerReviewOnAadhaar =>
      _profile != null && _reReviewStatuses.contains(_profile!.verificationStatus);

  Future<void> _save() async {
    final profile = _profile!;
    setState(() {
      _saving = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      await ref.read(profileRepositoryProvider).editAdvancedProfile(
            highestQualification: _qualification != profile.highestQualification ? _qualification : null,
            preferredCities: _preferredCitiesChanged(profile) ? _preferredCities : null,
          );
      setState(() => _successMessage = 'Saved. Your admin will see this change flagged for review.');
      await _load();
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _preferredCitiesChanged(CaregiverProfileModel profile) {
    final next = [..._preferredCities]..sort();
    final previous = [...profile.preferredCities]..sort();
    return next.join(',') != previous.join(',');
  }

  Future<void> _pickAndUploadSelfie() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null) return;
    setState(() {
      _uploadingDocType.add('selfie');
      _errorMessage = null;
    });
    try {
      final bytes = await photo.readAsBytes();
      await ref.read(profileRepositoryProvider).uploadSelfie(bytes, photo.name);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
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
      _errorMessage = null;
    });
    try {
      await ref.read(profileRepositoryProvider).uploadDocument(picked.bytes!, picked.name, documentType);
      final wasReReviewed = documentType == DocumentType.aadhaar && _willTriggerReviewOnAadhaar;
      await ref.read(sessionProvider.notifier).refreshStatus();
      await _load();
      if (wasReReviewed && mounted) {
        setState(() => _successMessage = 'Aadhaar updated. Your profile has been sent back for re-review.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _uploadingDocType.remove(documentType));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Advanced Profile')),
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
                      "Changes here will be reviewed by admin. Your current verification status is not affected — except re-uploading your Aadhaar card, which sends an available/unavailable profile back for re-review.",
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _qualification,
                    decoration: const InputDecoration(labelText: 'Highest Qualification', border: OutlineInputBorder()),
                    items: Qualification.all
                        .map((q) => DropdownMenuItem(value: q, child: Text(Qualification.displayNames[q] ?? q)))
                        .toList(),
                    onChanged: (value) => setState(() => _qualification = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                  const SizedBox(height: AppSpacing.md),
                  const Text('Preferred City (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  VitaMultiSelectChips(
                    options: City.all,
                    labels: City.displayNames,
                    selected: _preferredCities,
                    onChanged: (next) => setState(() => _preferredCities = next),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                  ],
                  if (_successMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_successMessage!, style: const TextStyle(color: AppColors.success)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
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
                  if (_willTriggerReviewOnAadhaar)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                      ),
                      child: const Text(
                        'Re-uploading your Aadhaar card will send your profile back for re-review.',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
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
                      isUploading:
                          _uploadingDocType.contains(DocumentType.other) && i == (_profile?.otherDocumentUrls.length ?? 0),
                      onTap: i <= (_profile?.otherDocumentUrls.length ?? 0)
                          ? () => _pickAndUploadDocument(DocumentType.other)
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
      ),
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
