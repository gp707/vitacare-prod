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
  String? _qualification;
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

  bool get _canSubmit =>
      !_submitting && _aadhaarUploaded && _qualification != null && _termsAccepted;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(profileRepositoryProvider).submitAdvanced(
            highestQualification: _qualification!,
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
                  // The only mandatory field left, explicitly labeled, so
                  // it's obvious up front what's blocking Submit.
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _qualification,
                    decoration: const InputDecoration(
                        labelText: 'Highest Qualification (mandatory)',
                        border: OutlineInputBorder()),
                    items: Qualification.all
                        .map((q) => DropdownMenuItem(
                            value: q, child: Text(Qualification.displayNames[q] ?? q)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _qualification = value),
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
