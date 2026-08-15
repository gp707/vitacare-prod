import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../audit_logs/data/audit_log_models.dart';
import '../../audit_logs/data/audit_logs_repository.dart';
import '../../audit_logs/screens/audit_logs_screen.dart' show formatAuditValue;
import '../data/admin_caregiver_models.dart';

/// Allowed status action buttons per SPEC.md 13.3 — every field (including
/// what used to be "Advanced Details") is now collected at registration, so
/// admin approves or rejects directly from pending_call in a single step.
const Map<String, List<String>> _statusActions = {
  'pending_call': ['available', 'rejected'],
};

class CaregiverDetailScreen extends ConsumerStatefulWidget {
  final String profileId;

  const CaregiverDetailScreen({super.key, required this.profileId});

  @override
  ConsumerState<CaregiverDetailScreen> createState() => _CaregiverDetailScreenState();
}

class _CaregiverDetailScreenState extends ConsumerState<CaregiverDetailScreen> {
  AdminCaregiverDetail? _detail;
  bool _loading = true;
  String? _errorMessage;
  bool _actionInFlight = false;

  List<AuditLogEntry> _auditEntries = [];
  bool _auditLoading = true;

  /// Which document slot ('selfie', 'qualification', 'aadhaar', 'other') is
  /// currently uploading, or null if none. Only one upload at a time.
  String? _uploadingDocType;

  final _internalNotesController = TextEditingController();
  final _remarksController = TextEditingController();

  bool _editMode = false;
  bool _savingEdits = false;
  final _fullNameController = TextEditingController();
  final _ageController = TextEditingController();
  String? _editGender;
  String? _editQualification;
  String? _editReligion;
  List<String> _editPreferredCities = [];
  List<String> _editLanguages = [];

  // Admin status override — unrestricted, any status from any status
  // (see PATCH /admin/caregivers/:id/status; no transition-matrix check).
  String? _overrideStatus;
  final _overrideRejectionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _internalNotesController.dispose();
    _remarksController.dispose();
    _fullNameController.dispose();
    _ageController.dispose();
    _overrideRejectionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final detail = await ref.read(adminCaregiversRepositoryProvider).getDetail(widget.profileId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _internalNotesController.text = detail.adminNotes.internalNotes ?? '';
        _remarksController.text = detail.adminNotes.availabilityRemarks ?? '';
      });
      unawaited(_loadAuditHistory(detail.userId));
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAuditHistory(String userId) async {
    setState(() => _auditLoading = true);
    try {
      final result = await ref
          .read(auditLogsRepositoryProvider)
          .list(AuditLogListFilters(targetUserId: userId, limit: 50));
      if (mounted) setState(() => _auditEntries = result.items);
    } on ApiException {
      // Non-critical: the rest of the caregiver detail page still works
      // without the audit tab, so failures here don't surface an error banner.
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  Future<void> _updateStatus(String status, {String? rejectionMessage}) async {
    setState(() => _actionInFlight = true);
    try {
      await ref
          .read(adminCaregiversRepositoryProvider)
          .updateStatus(widget.profileId, status, rejectionMessage: rejectionMessage);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  Future<void> _saveNotes() async {
    setState(() => _actionInFlight = true);
    try {
      await ref.read(adminCaregiversRepositoryProvider).upsertNotes(
            widget.profileId,
            internalNotes: _internalNotesController.text.trim().isEmpty
                ? null
                : _internalNotesController.text.trim(),
            availabilityRemarks:
                _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
          );
      if (mounted) _showSnackBar('Notes saved');
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  void _enterEditMode(AdminCaregiverDetail detail) {
    _fullNameController.text = detail.fullName;
    _ageController.text = detail.age.toString();
    setState(() {
      _editGender = detail.gender;
      _editQualification = detail.highestQualification;
      _editReligion = detail.religion;
      _editPreferredCities = List.from(detail.preferredCities);
      _editLanguages = List.from(detail.languages);
      _editMode = true;
    });
  }

  Future<void> _saveProfileEdits(AdminCaregiverDetail detail) async {
    setState(() => _savingEdits = true);
    try {
      final fields = <String, dynamic>{};

      final fullName = _fullNameController.text.trim();
      if (fullName.isNotEmpty && fullName != detail.fullName) fields['full_name'] = fullName;
      if (_editGender != null && _editGender != detail.gender) fields['gender'] = _editGender;
      final age = int.tryParse(_ageController.text.trim());
      if (age != null && age != detail.age) fields['age'] = age;
      if (_editQualification != detail.highestQualification) {
        fields['highest_qualification'] = _editQualification;
      }
      if (_editReligion != detail.religion) fields['religion'] = _editReligion;
      final sortedNewLangs = [..._editLanguages]..sort();
      final sortedOldLangs = [...detail.languages]..sort();
      if (sortedNewLangs.join(',') != sortedOldLangs.join(',')) fields['languages'] = _editLanguages;
      final sortedNewCities = [..._editPreferredCities]..sort();
      final sortedOldCities = [...detail.preferredCities]..sort();
      if (sortedNewCities.join(',') != sortedOldCities.join(',')) {
        fields['preferred_cities'] = _editPreferredCities;
      }

      if (fields.isNotEmpty) {
        await ref.read(adminCaregiversRepositoryProvider).editProfile(widget.profileId, fields);
      }

      if (mounted) {
        setState(() => _editMode = false);
        _showSnackBar('Profile updated');
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _savingEdits = false);
    }
  }

  Future<void> _pickAndUploadSelfie() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    setState(() => _uploadingDocType = 'selfie');
    try {
      await ref
          .read(adminCaregiversRepositoryProvider)
          .uploadSelfie(widget.profileId, picked.bytes!, picked.name);
      if (mounted) _showSnackBar('Selfie uploaded');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _uploadingDocType = null);
    }
  }

  Future<void> _pickAndUploadDocument(String documentType) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    setState(() => _uploadingDocType = documentType);
    try {
      await ref
          .read(adminCaregiversRepositoryProvider)
          .uploadDocument(widget.profileId, picked.bytes!, picked.name, documentType);
      if (mounted) _showSnackBar('Document uploaded');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _uploadingDocType = null);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : null),
    );
  }

  Future<void> _showRejectDialog() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject caregiver'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Rejection message (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed == true) {
      await _updateStatus(
        'rejected',
        rejectionMessage: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.caregivers,
      child: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : _errorMessage != null
                ? Center(child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error)))
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final detail = _detail!;
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(detail.phone, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                VitaStatusBadge(status: detail.verificationStatus),
                const SizedBox(width: AppSpacing.md),
                Text('Registered ${detail.createdAt.split('T').first}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _buildActionButtons(detail),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: _buildStatusOverride(),
          ),
          const SizedBox(height: AppSpacing.md),
          const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            tabs: [Tab(text: 'Profile'), Tab(text: 'Documents'), Tab(text: 'Notes'), Tab(text: 'Audit History')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildProfileTab(detail),
                _buildDocumentsTab(detail),
                _buildNotesTab(),
                _buildAuditTab(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AdminCaregiverDetail detail) {
    final buttons = <Widget>[];
    final actions = _statusActions[detail.verificationStatus] ?? [];
    for (final action in actions) {
      if (action == 'rejected') {
        buttons.add(OutlinedButton(
          onPressed: _actionInFlight ? null : _showRejectDialog,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Reject'),
        ));
      } else if (action == 'available') {
        buttons.add(ElevatedButton(
          onPressed: _actionInFlight ? null : () => _updateStatus('available'),
          child: const Text('Approve'),
        ));
      }
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: AppSpacing.sm, children: buttons);
  }

  /// Free-form override, separate from the curated quick-action buttons
  /// above — any status, from any status, no transition-matrix check
  /// (matches the backend's deliberately-unrestricted endpoint).
  Widget _buildStatusOverride() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          const Text('Admin Override:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          DropdownButton<String>(
            value: _overrideStatus,
            hint: const Text('Set status to...'),
            items: VerificationStatus.all
                .map((s) => DropdownMenuItem(value: s, child: Text(_statusLabel(s))))
                .toList(),
            onChanged: _actionInFlight ? null : (value) => setState(() => _overrideStatus = value),
          ),
          if (_overrideStatus == VerificationStatus.rejected)
            SizedBox(
              width: 260,
              child: TextField(
                controller: _overrideRejectionController,
                decoration: const InputDecoration(labelText: 'Rejection message (optional)', isDense: true),
              ),
            ),
          ElevatedButton(
            onPressed: (_actionInFlight || _overrideStatus == null)
                ? null
                : () {
                    final status = _overrideStatus!;
                    final rejectionMessage = status == VerificationStatus.rejected
                        ? (_overrideRejectionController.text.trim().isEmpty
                            ? null
                            : _overrideRejectionController.text.trim())
                        : null;
                    setState(() {
                      _overrideStatus = null;
                      _overrideRejectionController.clear();
                    });
                    _updateStatus(status, rejectionMessage: rejectionMessage);
                  },
            child: const Text('Set Status'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) =>
      status.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  Widget _buildProfileTab(AdminCaregiverDetail detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _editMode
                ? TextButton(
                    onPressed: _savingEdits ? null : () => setState(() => _editMode = false),
                    child: const Text('Cancel'),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _enterEditMode(detail),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_editMode) _buildProfileEditForm(detail) else _buildProfileReadOnly(detail),
        ],
      ),
    );
  }

  Widget _buildProfileReadOnly(AdminCaregiverDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Gender', detail.gender),
        _field('Age', '${detail.age}'),
        _field('Languages', detail.languages.join(', ')),
        _field('Qualification', Qualification.displayNames[detail.highestQualification] ?? detail.highestQualification ?? '-'),
        _field('Religion', detail.religion ?? '-'),
        _field('Preferred City', detail.preferredCities.isEmpty ? '-' : detail.preferredCities.join(', ')),
        _field('Terms Accepted', detail.termsAccepted ? 'Yes' : 'No'),
        _field('Has Pending Edits', detail.hasPendingEdits ? 'Yes' : 'No'),
        if (detail.rejectionMessage != null) _field('Rejection Message', detail.rejectionMessage!),
      ],
    );
  }

  Widget _buildProfileEditForm(AdminCaregiverDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fullNameController,
                decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _editGender,
            decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
            items: Gender.all.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (value) => setState(() => _editGender = value),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Languages', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.xs),
        VitaMultiSelectChips(
          options: Language.all,
          labels: Language.displayNames,
          selected: _editLanguages,
          onChanged: (next) => setState(() => _editLanguages = next),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Preferred City', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.xs),
        VitaMultiSelectChips(
          options: City.all,
          labels: City.displayNames,
          selected: _editPreferredCities,
          onChanged: (next) => setState(() => _editPreferredCities = next),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _editQualification,
                decoration:
                    const InputDecoration(labelText: 'Qualification', border: OutlineInputBorder()),
                items: Qualification.all
                    .map((q) => DropdownMenuItem<String?>(value: q, child: Text(Qualification.displayNames[q] ?? q)))
                    .toList(),
                onChanged: (value) => setState(() => _editQualification = value),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _editReligion,
                decoration: const InputDecoration(labelText: 'Religion', border: OutlineInputBorder()),
                items: Religion.all
                    .map((r) => DropdownMenuItem<String?>(value: r, child: Text(Religion.displayNames[r] ?? r)))
                    .toList(),
                onChanged: (value) => setState(() => _editReligion = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(
          onPressed: _savingEdits ? null : () => _saveProfileEdits(detail),
          child: _savingEdits
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }

  Widget _buildDocumentsTab(AdminCaregiverDetail detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _documentRow('Selfie', detail.selfiePhotoUrl, onUpload: _pickAndUploadSelfie, isUploading: _uploadingDocType == 'selfie'),
          _documentRow(
            'Qualification Document',
            detail.qualificationDocumentUrl,
            onUpload: () => _pickAndUploadDocument(DocumentType.qualification),
            isUploading: _uploadingDocType == DocumentType.qualification,
          ),
          _documentRow(
            'Aadhaar Card',
            detail.aadhaarDocumentUrl,
            onUpload: () => _pickAndUploadDocument(DocumentType.aadhaar),
            isUploading: _uploadingDocType == DocumentType.aadhaar,
          ),
          for (var i = 0; i < detail.otherDocumentUrls.length; i++)
            _documentRow('Other Document ${i + 1}', detail.otherDocumentUrls[i]),
          if (detail.otherDocumentUrls.length < Validation.maxOtherDocuments) ...[
            const SizedBox(height: AppSpacing.sm),
            _uploadingDocType == DocumentType.other
                ? const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
                : OutlinedButton.icon(
                    onPressed: () => _pickAndUploadDocument(DocumentType.other),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Other Document'),
                  ),
          ],
        ],
      ),
    );
  }

  /// [onUpload] is omitted for already-full "other document" slots, which
  /// are add-only (a new slot each time, not replaceable in place).
  Widget _documentRow(String label, String? url, {VoidCallback? onUpload, bool isUploading = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: 200, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: url == null
                ? const Text('Not uploaded', style: TextStyle(color: AppColors.textSecondary))
                : TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View / Download'),
                  ),
          ),
          if (onUpload != null)
            if (isUploading)
              const SizedBox(height: 20, width: 20, child: VitaLoadingIndicator(size: 20))
            else
              OutlinedButton(
                onPressed: onUpload,
                child: Text(url == null ? 'Upload' : 'Replace'),
              ),
        ],
      ),
    );
  }

  Widget _buildNotesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _internalNotesController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Internal Notes', border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _remarksController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Availability Remarks', border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(onPressed: _actionInFlight ? null : _saveNotes, child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _buildAuditTab(AdminCaregiverDetail detail) {
    if (_auditLoading) {
      return const Center(child: VitaLoadingIndicator());
    }
    if (_auditEntries.isEmpty) {
      return const Center(child: Text('No audit history for this caregiver yet.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/audit-logs', arguments: detail.userId),
              child: const Text('View full audit log'),
            ),
          ),
          for (final entry in _auditEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(entry.action, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            entry.createdAt.replaceFirst('T', ' ').split('.').first,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('By: ${entry.userName ?? 'system'}'),
                      if (entry.beforeValue != null)
                        Text('Before: ${formatAuditValue(entry.beforeValue)}'),
                      if (entry.afterValue != null)
                        Text('After: ${formatAuditValue(entry.afterValue)}'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 220, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
