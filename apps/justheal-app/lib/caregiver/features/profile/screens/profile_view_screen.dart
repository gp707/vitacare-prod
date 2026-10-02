import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/image_compression.dart';
import '../../../core/utils/upload_size_limit.dart';
import '../../auth/state/session_notifier.dart';
import '../status_message.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/messages_bell.dart';

const _reReviewStatuses = [
  VerificationStatus.available,
  VerificationStatus.unavailable,
  VerificationStatus.rejected,
];

/// The caregiver's own profile — a single screen combining what used to be
/// a read-only view plus a separate "Edit Profile" page. Every field the
/// caregiver may actually change (Age, Languages, Highest Qualification,
/// Login PIN, and document uploads) is edited inline right here: a pencil
/// icon next to the current value, tapping it turns that one field into an
/// editable input in place with its own Save/Cancel icons — no navigating
/// away. full_name, phone, and gender are shown read-only (only admins can
/// change full_name/gender; phone self-service change was removed from the
/// product entirely — see the WhatsApp pointer text below Phone). Religion
/// is also read-only — locked from self-edit once set at registration.
/// Editing anything here while rejected auto-resubmits (server-side) — no
/// separate "resubmit" action needed.
class ProfileViewScreen extends ConsumerStatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  ConsumerState<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends ConsumerState<ProfileViewScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;
  String? _errorMessage;

  final Set<String> _uploadingDocType = {};
  String? _docError;
  String? _docSuccess;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _willTriggerReview =>
      _profile != null && _reReviewStatuses.contains(_profile!.verificationStatus);

  /// Shared save feedback for every inline field below (Age, Languages,
  /// Qualification, PIN) — reflects the same "flagged for review, or
  /// resubmitted if this account was rejected" behavior the old always-
  /// visible edit form used to show as a persistent success line, now
  /// surfaced as a transient SnackBar since the field itself already shows
  /// the saved value in place.
  void _showSavedSnackBar({required bool wasRejected, required String? newStatus}) {
    if (!mounted) return;
    final resubmitted = wasRejected && newStatus == VerificationStatus.pendingCall;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resubmitted
              ? 'Saved. Your profile has been resubmitted for review.'
              : 'Saved. Your admin will see this change flagged for review.',
        ),
      ),
    );
  }

  Future<String?> _saveAge(String value) async {
    final age = int.tryParse(value.trim());
    if (age == null || !Validators.isValidAge(age)) {
      return 'Age must be between ${Validation.ageMin} and ${Validation.ageMax}';
    }
    final wasRejected = _profile?.verificationStatus == VerificationStatus.rejected;
    try {
      final status = await ref.read(profileRepositoryProvider).editProfile(age: age);
      await _load();
      _showSavedSnackBar(wasRejected: wasRejected, newStatus: status);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _saveLanguages(List<String> languages) async {
    if (languages.isEmpty) return 'Select at least one language';
    final wasRejected = _profile?.verificationStatus == VerificationStatus.rejected;
    try {
      final status = await ref.read(profileRepositoryProvider).editProfile(languages: languages);
      await _load();
      _showSavedSnackBar(wasRejected: wasRejected, newStatus: status);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _saveQualification(String qualification) async {
    final wasRejected = _profile?.verificationStatus == VerificationStatus.rejected;
    try {
      final status = await ref.read(profileRepositoryProvider).editProfile(highestQualification: qualification);
      await _load();
      _showSavedSnackBar(wasRejected: wasRejected, newStatus: status);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _saveCode(String code) async {
    if (!Validators.isValidCode(code)) return 'Code must be exactly 4 digits';
    try {
      await ref.read(profileRepositoryProvider).updateCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login code updated.')));
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// True (and sets a friendly error) if [sizeBytes] exceeds [maxBytes]
  /// (the shared 10MB limit by default; Selfie/Aadhaar pass the tighter
  /// 4MB [photoAadhaarMaxSizeBytes] instead) — checked immediately on pick
  /// so an oversized file never even reaches the upload step, rather than
  /// failing later with the backend's own less specific error.
  bool _rejectIfTooLarge(int sizeBytes, {int? maxBytes, String? message}) {
    final limit = maxBytes ?? Validation.fileMaxSizeBytes;
    if (sizeBytes <= limit) return false;
    setState(() => _docError =
        message ?? 'That file is larger than ${Validation.fileMaxSizeMb}MB. Please choose a smaller file.');
    return true;
  }

  Future<void> _pickAndUploadSelfie() async {
    final picker = ImagePicker();
    // maxWidth/maxHeight cap the resolution the camera plugin itself
    // downsamples to — a profile/identity photo never needs full camera
    // resolution, and this keeps a typical re-uploaded selfie in the
    // tens-of-KB range instead of several hundred.
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    if (_rejectIfTooLarge(bytes.length, maxBytes: photoAadhaarMaxSizeBytes, message: photoAadhaarTooLargeMessage)) {
      return;
    }
    setState(() {
      _uploadingDocType.add('selfie');
      _docError = null;
      _docSuccess = null;
    });
    try {
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
    // Compressed first, then size-checked against the compressed bytes —
    // a high-res photo that's over the limit uncompressed can still
    // succeed once shrunk. Non-image files pass through untouched.
    final compressed = await compressImageIfPossible(picked.bytes!, picked.name);
    final isAadhaar = documentType == DocumentType.aadhaar;
    if (_rejectIfTooLarge(
      compressed.bytes.length,
      maxBytes: isAadhaar ? photoAadhaarMaxSizeBytes : null,
      message: isAadhaar ? photoAadhaarTooLargeMessage : null,
    )) {
      return;
    }

    setState(() {
      _uploadingDocType.add(documentType);
      _docError = null;
      _docSuccess = null;
    });
    try {
      final wasReReviewed = documentType == DocumentType.aadhaar && _willTriggerReview;
      await ref.read(profileRepositoryProvider).uploadDocument(compressed.bytes, compressed.filename, documentType);
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

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await ref.read(sessionProvider.notifier).logout();
    navigator.pushNamedAndRemoveUntil('/caregiver/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(child: VitaAppBarTitle('My Profile')),
            if (_profile != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: VitaStatusBadge(status: _profile!.verificationStatus)),
            ],
          ],
        ),
        actions: caregiverAppBarActions(showBell: true),
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: const CaregiverBottomNav(currentIndex: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: VitaLoadingIndicator())
              : _errorMessage != null
                  ? ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                      ],
                    )
                  : _buildContent(context, _profile!),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, CaregiverProfileModel profile) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          statusMessageFor(profile.verificationStatus, profile.rejectionMessage),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Basic Info',
          trailing: caregiverDisplayId(profile.caregiverNumber) != null
              ? Text(
                  'Nurse Id: ${caregiverDisplayId(profile.caregiverNumber)}',
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
                )
              : null,
          children: [
            _Field(Icons.badge, 'Full Name', profile.fullName),
            _Field(Icons.phone, 'Phone', profile.phone),
            const Padding(
              padding: EdgeInsets.only(left: 30, bottom: AppSpacing.xs),
              child: Text(
                "To change the mobile number linked to your account, tap the Help button above to "
                "chat with us on WhatsApp and let us know.",
                style: TextStyle(color: AppColors.success, fontSize: AppTypography.caption),
              ),
            ),
            _Field(Icons.wc, 'Gender', profile.gender[0].toUpperCase() + profile.gender.substring(1)),
            _EditableTextField(
              icon: Icons.cake,
              label: 'Age',
              value: '${profile.age}',
              keyboardType: TextInputType.number,
              onSave: _saveAge,
            ),
            _EditableChipsField(
              icon: Icons.language,
              label: 'Languages',
              value: profile.languages,
              onSave: _saveLanguages,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Professional & Contact Info',
          children: [
            _EditableDropdownField(
              icon: Icons.school,
              label: 'Qualification',
              value: profile.highestQualification,
              displayValue: Qualification.displayNames[profile.highestQualification] ?? '—',
              items: Qualification.all
                  .map((q) => DropdownMenuItem(value: q, child: Text(Qualification.displayNames[q] ?? q)))
                  .toList(),
              onSave: _saveQualification,
            ),
            _Field(Icons.diversity_3, 'Religion', Religion.displayNames[profile.religion] ?? '—'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Login PIN',
          children: [_EditablePinField(onSave: _saveCode)],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: 'Documents',
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Selfie and Aadhaar Card must each be under ${photoAadhaarMaxSizeMb}MB. '
                'Qualification Document and Other Documents must each be under ${Validation.fileMaxSizeMb}MB.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
              ),
            ),
            _DocumentSlot(
              title: 'Selfie (mandatory)',
              uploaded: profile.selfiePhotoUrl != null,
              isUploading: _uploadingDocType.contains('selfie'),
              onTap: _pickAndUploadSelfie,
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentSlot(
              title: 'Aadhaar Card (mandatory)',
              uploaded: profile.aadhaarDocumentUrl != null,
              isUploading: _uploadingDocType.contains(DocumentType.aadhaar),
              onTap: () => _pickAndUploadDocument(DocumentType.aadhaar),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentSlot(
              title: 'Qualification Document (optional)',
              uploaded: profile.qualificationDocumentUrl != null,
              isUploading: _uploadingDocType.contains(DocumentType.qualification),
              onTap: () => _pickAndUploadDocument(DocumentType.qualification),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < Validation.maxOtherDocuments; i++) ...[
              _DocumentSlot(
                title: 'Other document ${i + 1}',
                uploaded: i < profile.otherDocumentUrls.length,
                isUploading: _uploadingDocType.contains(DocumentType.other) && i == profile.otherDocumentUrls.length,
                onTap: i <= profile.otherDocumentUrls.length ? () => _pickAndUploadDocument(DocumentType.other) : null,
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
        const Divider(height: AppSpacing.xxl),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, size: 16, color: AppColors.error),
          label: const Text('Logout', style: TextStyle(color: AppColors.error)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  // Shown at the far end of the title row — currently only the Basic Info
  // section's own "Nurse Id: <id>" line.
  final Widget? trailing;

  const _Section({required this.title, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.error, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold, color: AppColors.success)),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Field(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldIcon(icon),
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldIcon extends StatelessWidget {
  final IconData icon;
  const _FieldIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: AppSpacing.xs),
      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 13, color: AppColors.primaryDark),
    );
  }
}

/// Shared "pencil icon → inline edit in place" chrome for every editable
/// field below — the label/value header row always looks exactly like a
/// plain read-only [_Field] (same icon avatar, same fixed-width bold
/// label) so a caregiver scanning the section sees no visual difference
/// until they actually tap the pencil. The editor itself renders on its
/// own row underneath once tapped, rather than squeezing into the header
/// row — a dropdown or a chip picker needs more width than a single-line
/// value ever did, and reusing the header row's tight layout for both
/// would overflow on a narrow phone.
abstract class _EditableFieldRow<T> extends StatefulWidget {
  final IconData icon;
  final String label;

  const _EditableFieldRow({required this.icon, required this.label});
}

abstract class _EditableFieldRowState<T, W extends _EditableFieldRow<T>> extends State<W> {
  bool editing = false;
  bool saving = false;
  String? error;

  /// Resets any local editing state (e.g. a controller's text) back to
  /// this field's current committed value — called both when entering
  /// edit mode and when cancelling out of it.
  void resetEditingState();

  Widget buildEditor(BuildContext context);
  String buildDisplayValue();
  String? validateBeforeSave();
  Future<String?> save();

  void startEditing() => setState(() {
        resetEditingState();
        editing = true;
        error = null;
      });

  void cancel() => setState(() {
        editing = false;
        error = null;
        resetEditingState();
      });

  Future<void> handleSave() async {
    final validationError = validateBeforeSave();
    if (validationError != null) {
      setState(() => error = validationError);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final saveError = await save();
    if (!mounted) return;
    setState(() {
      saving = false;
      if (saveError != null) {
        error = saveError;
      } else {
        editing = false;
      }
    });
  }

  Widget _trailingAction() {
    if (editing && saving) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16)),
      );
    }
    if (editing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check, color: AppColors.success, size: 20),
            tooltip: 'Save',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: handleSave,
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.error, size: 20),
            tooltip: 'Cancel',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: cancel,
          ),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.edit, size: 16, color: AppColors.primaryDark),
      tooltip: 'Edit ${widget.label}',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: startEditing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldIcon(widget.icon),
              SizedBox(
                width: 130,
                child: Text(widget.label, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: editing
                    ? const SizedBox.shrink()
                    : Text(buildDisplayValue(), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
              ),
              _trailingAction(),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: buildEditor(context),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: AppSpacing.xs),
              child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
            ),
        ],
      ),
    );
  }
}

class _EditableTextField extends _EditableFieldRow<String> {
  final String value;
  final TextInputType? keyboardType;
  final Future<String?> Function(String value) onSave;

  const _EditableTextField({
    required super.icon,
    required super.label,
    required this.value,
    required this.onSave,
    this.keyboardType,
  });

  @override
  State<_EditableTextField> createState() => _EditableTextFieldState();
}

class _EditableTextFieldState extends _EditableFieldRowState<String, _EditableTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _EditableTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!editing && widget.value != oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void resetEditingState() => _controller.text = widget.value;

  @override
  String? validateBeforeSave() => null;

  @override
  Future<String?> save() => widget.onSave(_controller.text.trim());

  @override
  Widget buildEditor(BuildContext context) => TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label, isDense: true, border: const OutlineInputBorder()),
      );

  @override
  String buildDisplayValue() => widget.value;
}

class _EditableDropdownField extends _EditableFieldRow<String?> {
  final String? value;
  final String displayValue;
  final List<DropdownMenuItem<String>> items;
  final Future<String?> Function(String value) onSave;

  const _EditableDropdownField({
    required super.icon,
    required super.label,
    required this.value,
    required this.displayValue,
    required this.items,
    required this.onSave,
  });

  @override
  State<_EditableDropdownField> createState() => _EditableDropdownFieldState();
}

class _EditableDropdownFieldState extends _EditableFieldRowState<String?, _EditableDropdownField> {
  late String? _pending = widget.value;

  @override
  void resetEditingState() => _pending = widget.value;

  @override
  String? validateBeforeSave() => _pending == null ? 'Select a value' : null;

  @override
  Future<String?> save() => widget.onSave(_pending!);

  @override
  Widget buildEditor(BuildContext context) => DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _pending,
        decoration: InputDecoration(labelText: widget.label, isDense: true, border: const OutlineInputBorder()),
        items: widget.items,
        onChanged: (v) => setState(() => _pending = v),
      );

  @override
  String buildDisplayValue() => widget.displayValue;
}

class _EditableChipsField extends _EditableFieldRow<List<String>> {
  final List<String> value;
  final Future<String?> Function(List<String> value) onSave;

  const _EditableChipsField({
    required super.icon,
    required super.label,
    required this.value,
    required this.onSave,
  });

  @override
  State<_EditableChipsField> createState() => _EditableChipsFieldState();
}

class _EditableChipsFieldState extends _EditableFieldRowState<List<String>, _EditableChipsField> {
  late List<String> _pending = [...widget.value];

  @override
  void resetEditingState() => _pending = [...widget.value];

  @override
  String? validateBeforeSave() => _pending.isEmpty ? 'Select at least one language' : null;

  @override
  Future<String?> save() => widget.onSave(_pending);

  @override
  Widget buildEditor(BuildContext context) => VitaMultiSelectChips(
        options: Language.all,
        labels: Language.displayNames,
        selected: _pending,
        onChanged: (next) => setState(() => _pending = next),
      );

  @override
  String buildDisplayValue() => widget.value.map((l) => Language.displayNames[l] ?? l).join(', ');
}

class _EditablePinField extends StatefulWidget {
  final Future<String?> Function(String code) onSave;

  const _EditablePinField({required this.onSave});

  @override
  State<_EditablePinField> createState() => _EditablePinFieldState();
}

class _EditablePinFieldState extends State<_EditablePinField> {
  bool _editing = false;
  bool _saving = false;
  String? _error;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() => setState(() {
        _controller.clear();
        _editing = true;
        _error = null;
      });

  void _cancel() => setState(() {
        _editing = false;
        _error = null;
        _controller.clear();
      });

  Future<void> _save() async {
    final code = _controller.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(code);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error != null) {
        _error = error;
      } else {
        _editing = false;
        _controller.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldIcon(Icons.lock_outline),
              const SizedBox(
                width: 130,
                child: Text('Login PIN', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: _editing
                    ? const SizedBox.shrink()
                    : const Text('••••', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
              if (_editing && _saving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(height: 16, width: 16, child: VitaLoadingIndicator(size: 16)),
                )
              else if (_editing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: AppColors.success, size: 20),
                      tooltip: 'Save',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _save,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.error, size: 20),
                      tooltip: 'Cancel',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _cancel,
                    ),
                  ],
                )
              else
                IconButton(
                  icon: const Icon(Icons.edit, size: 16, color: AppColors.primaryDark),
                  tooltip: 'Edit Login PIN',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _startEditing,
                ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: Validation.codeLength,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'New 4-Digit PIN', isDense: true, border: OutlineInputBorder()),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: AppSpacing.xs),
              child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
            ),
        ],
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
        color: AppColors.success.withValues(alpha: 0.06),
        border: Border.all(color: uploaded ? AppColors.error : AppColors.textSecondary, width: 2.5),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        children: [
          Icon(
            uploaded ? Icons.check_circle : Icons.insert_drive_file_outlined,
            color: uploaded ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: uploaded ? AppColors.success : AppColors.textSecondary,
                    fontWeight: FontWeight.bold))),
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
