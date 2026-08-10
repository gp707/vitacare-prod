import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../../app/route_for_status.dart';

class AdvancedDetailsScreen extends ConsumerStatefulWidget {
  const AdvancedDetailsScreen({super.key});

  @override
  ConsumerState<AdvancedDetailsScreen> createState() =>
      _AdvancedDetailsScreenState();
}

class _AdvancedDetailsScreenState extends ConsumerState<AdvancedDetailsScreen> {
  final _fatherNameController = TextEditingController();
  final _fatherPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  String? _qualification;
  String? _religion;
  final List<String> _preferredCities = [];
  bool _termsAccepted = false;

  bool _loadingDocs = true;
  bool _qualificationUploaded = false;
  bool _aadhaarUploaded = false;
  int _otherCount = 0;
  final Set<String> _uploadingDocType = {};
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _fatherNameController.dispose();
    _fatherPhoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// One-time load on entry — prefills text fields from any previous
  /// submission (a first-time call_verified submission has these all null,
  /// so it's a no-op there; a rejected caregiver resubmitting sees their
  /// last-submitted values instead of a blank form).
  Future<void> _loadProfile() async {
    setState(() => _loadingDocs = true);
    try {
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      if (mounted) {
        setState(() {
          _qualificationUploaded = profile.qualificationDocumentUrl != null;
          _aadhaarUploaded = profile.aadhaarDocumentUrl != null;
          _otherCount = profile.otherDocumentUrls.length;
          _qualification = profile.highestQualification;
          _religion = profile.religion;
          _preferredCities
            ..clear()
            ..addAll(profile.preferredCities);
          _fatherNameController.text = profile.fatherName ?? '';
          _fatherPhoneController.text =
              (profile.fatherPhone ?? '').replaceFirst('+91', '');
          _addressController.text = profile.currentAddress ?? '';
          _notesController.text = profile.notes ?? '';
          _termsAccepted = profile.termsAccepted;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  /// Re-fetches only the document-upload flags after an upload — unlike
  /// _loadProfile, does NOT touch the text/dropdown fields, so it never
  /// clobbers what the caregiver is actively typing.
  Future<void> _refreshDocumentStatus() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      if (mounted) {
        setState(() {
          _qualificationUploaded = profile.qualificationDocumentUrl != null;
          _aadhaarUploaded = profile.aadhaarDocumentUrl != null;
          _otherCount = profile.otherDocumentUrls.length;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _pickAndUpload(String documentType) async {
    // withData: true — PlatformFile.path is always null on Flutter Web (no
    // filesystem access in the browser), so bytes are the only
    // cross-platform way to get the picked file's content.
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    setState(() {
      _uploadingDocType.add(documentType);
      _errorMessage = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .uploadDocument(picked.bytes!, picked.name, documentType);
      await _refreshDocumentStatus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _uploadingDocType.remove(documentType));
    }
  }

  // Father's name/phone and Current Address are optional — if left blank
  // they're omitted from submission, but if the caregiver does type
  // something in father's name/phone it must still be validly formatted.
  bool get _canSubmit =>
      !_submitting &&
      _aadhaarUploaded &&
      _qualification != null &&
      _religion != null &&
      (_fatherNameController.text.trim().isEmpty ||
          Validators.isValidName(_fatherNameController.text.trim())) &&
      (_fatherPhoneController.text.trim().isEmpty ||
          Validators.isValidPhone(
              '+91${_fatherPhoneController.text.trim()}')) &&
      _termsAccepted;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final fatherName = _fatherNameController.text.trim();
      final fatherPhone = _fatherPhoneController.text.trim();
      final currentAddress = _addressController.text.trim();
      await ref.read(profileRepositoryProvider).submitAdvanced(
            highestQualification: _qualification!,
            religion: _religion!,
            fatherName: fatherName.isEmpty ? null : fatherName,
            fatherPhone: fatherPhone.isEmpty ? null : '+91$fatherPhone',
            currentAddress: currentAddress.isEmpty ? null : currentAddress,
            preferredCities: _preferredCities,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      await ref.read(sessionProvider.notifier).loadSession();
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session is SessionAuthenticated) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(routeForStatus(session), (route) => false);
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Details'),
        actions: [
          TextButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              ref.read(sessionProvider.notifier).logout().then((_) {
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              });
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        // Gated on the initial load (not per-upload refreshes) — the
        // dropdowns below use `initialValue`, which Flutter's FormField
        // only reads once at first build, so the whole form must not be
        // constructed until the prefilled values (if any) are known.
        child: _loadingDocs
            ? const Center(child: VitaLoadingIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  // Mandatory fields first, each explicitly labeled, so it's
                  // obvious up front what's blocking Submit — optional
                  // fields (father's info, preferred city, etc.) follow.
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _qualification,
                    decoration: const InputDecoration(
                        labelText: 'Highest Qualification (mandatory)',
                        border: OutlineInputBorder()),
                    items: Qualification.all
                        .map((q) => DropdownMenuItem(
                            value: q, child: Text(q.replaceAll('_', ' '))))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _qualification = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _religion,
                    decoration: const InputDecoration(
                        labelText: 'Religion (mandatory)',
                        border: OutlineInputBorder()),
                    items: Religion.all
                        .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(Religion.displayNames[r] ?? r)))
                        .toList(),
                    onChanged: (value) => setState(() => _religion = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _addressController,
                    maxLines: 3,
                    maxLength: Validation.addressMaxLength,
                    decoration: const InputDecoration(
                        labelText: 'Current Address (optional)',
                        border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Documents',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.sm),
                  _DocumentSlot(
                    title: 'Aadhaar Card (mandatory)',
                    uploaded: _aadhaarUploaded,
                    isUploading:
                        _uploadingDocType.contains(DocumentType.aadhaar),
                    onTap: () => _pickAndUpload(DocumentType.aadhaar),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DocumentSlot(
                    title: 'Qualification Document (optional)',
                    uploaded: _qualificationUploaded,
                    isUploading:
                        _uploadingDocType.contains(DocumentType.qualification),
                    onTap: () => _pickAndUpload(DocumentType.qualification),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Other Documents (optional, up to ${Validation.maxOtherDocuments})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (int i = 0; i < Validation.maxOtherDocuments; i++) ...[
                    _DocumentSlot(
                      title: 'Other document ${i + 1}',
                      uploaded: i < _otherCount,
                      isUploading:
                          _uploadingDocType.contains(DocumentType.other) &&
                              i == _otherCount,
                      onTap: i <= _otherCount
                          ? () => _pickAndUpload(DocumentType.other)
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _fatherNameController,
                    decoration: const InputDecoration(
                        labelText: "Father's Name (optional)",
                        border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _fatherPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      prefixText: '+91 ',
                      labelText: "Father's Phone (optional)",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Preferred City (optional)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
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
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    maxLength: Validation.notesMaxLength,
                    decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CheckboxListTile(
                    value: _termsAccepted,
                    onChanged: (value) =>
                        setState(() => _termsAccepted = value ?? false),
                    title: const Text('I accept the Terms & Conditions (mandatory)'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_errorMessage!,
                        style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit'),
                  ),
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
            const SizedBox(
                height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
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
