import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../audit_logs/data/audit_log_models.dart';
import '../../audit_logs/screens/audit_logs_screen.dart' show formatAuditValue;
import '../../audit_logs/widgets/audit_entry_cells.dart';
import '../../audit_logs/widgets/scoped_audit_history_section.dart';
import '../../../shared/widgets/reset_pin_dialog.dart';
import '../data/admin_organisations_repository.dart';

/// organisation_profiles.city accepts the existing 7 cities plus this one
/// extra sentinel — a separate org-scoped list, not an extension of the
/// shared City enum (see "NurseNow" in CLAUDE.md).
const _organisationCityOthers = 'others';

/// Mirrors IndividualDetailScreen — a single-page detail view (no tabs)
/// with an edit form for the organisation's editable fields, plus a
/// scoped audit-history preview and a link to the full log.
class OrganisationDetailScreen extends ConsumerStatefulWidget {
  final String userId;

  const OrganisationDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<OrganisationDetailScreen> createState() =>
      _OrganisationDetailScreenState();
}

class _OrganisationDetailScreenState
    extends ConsumerState<OrganisationDetailScreen> {
  AdminOrganisationListItem? _detail;
  bool _loading = true;
  String? _errorMessage;

  bool _editMode = false;
  bool _savingEdits = false;
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _organisationNameController = TextEditingController();
  final _areaController = TextEditingController();
  String? _editOrganisationType;
  String? _editCity;

  bool _editingNotes = false;
  bool _savingNotes = false;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _organisationNameController.dispose();
    _areaController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final detail = await ref
          .read(adminOrganisationsRepositoryProvider)
          .getDetail(widget.userId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enterEditMode(AdminOrganisationListItem detail) {
    _fullNameController.text = detail.fullName;
    _phoneController.text = detail.phone;
    _organisationNameController.text = detail.organisationName;
    _areaController.text = detail.area;
    setState(() {
      _editOrganisationType = detail.organisationType;
      _editCity = detail.city;
      _editMode = true;
    });
  }

  Future<void> _saveEdits(AdminOrganisationListItem detail) async {
    setState(() => _savingEdits = true);
    try {
      final fields = <String, dynamic>{};

      final fullName = _fullNameController.text.trim();
      if (fullName.isNotEmpty && fullName != detail.fullName) {
        fields['full_name'] = fullName;
      }
      final phone = _phoneController.text.trim();
      if (phone.isNotEmpty && phone != detail.phone) {
        fields['phone'] = phone;
      }
      final organisationName = _organisationNameController.text.trim();
      if (organisationName.isNotEmpty &&
          organisationName != detail.organisationName) {
        fields['organisation_name'] = organisationName;
      }
      if (_editOrganisationType != null &&
          _editOrganisationType != detail.organisationType) {
        fields['organisation_type'] = _editOrganisationType;
      }
      if (_editCity != null && _editCity != detail.city) {
        fields['city'] = _editCity;
      }
      final area = _areaController.text.trim();
      if (area.isNotEmpty && area != detail.area) fields['area'] = area;

      if (fields.isNotEmpty) {
        await ref
            .read(adminOrganisationsRepositoryProvider)
            .editProfile(widget.userId, fields);
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

  /// Same block/unblock flow as OrganisationsListScreen's own row menu —
  /// previously only reachable from the list, never from this full-profile
  /// view.
  Future<void> _showBlockDialog(AdminOrganisationListItem detail, String level) async {
    final controller = TextEditingController();
    final label = level == 'full' ? 'Block completely' : 'Block from posting new requirements';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label — ${detail.organisationName}'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Reason (shown to the organisation)'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminOrganisationsRepositoryProvider).block(detail.userId, level, controller.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    }
  }

  Future<void> _unblock(AdminOrganisationListItem detail, String level) async {
    try {
      await ref.read(adminOrganisationsRepositoryProvider).unblock(detail.userId, level);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    }
  }

  Future<void> _resetPin(AdminOrganisationListItem detail) async {
    final newCode = await showResetPinDialog(context, accountLabel: detail.organisationName);
    if (newCode == null) return;
    try {
      await ref.read(adminOrganisationsRepositoryProvider).resetCode(detail.userId, newCode);
      if (mounted) _showSnackBar('PIN reset');
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    }
  }

  void _enterEditNotes(AdminOrganisationListItem detail) {
    _notesController.text = detail.notes ?? '';
    setState(() => _editingNotes = true);
  }

  Future<void> _saveNotes(AdminOrganisationListItem detail) async {
    setState(() => _savingNotes = true);
    try {
      await ref
          .read(adminOrganisationsRepositoryProvider)
          .upsertNotes(widget.userId, _notesController.text.trim());
      if (mounted) {
        setState(() => _editingNotes = false);
        _showSnackBar('Notes saved');
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.rehabHospitals,
      child: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : _errorMessage != null
                ? Center(
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: AppColors.error)))
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final detail = _detail!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.organisationName,
                        style: const TextStyle(
                            fontSize: AppTypography.heading, fontWeight: FontWeight.bold)),
                    if (organisationDisplayId(detail.orgNumber) != null)
                      Text(organisationDisplayId(detail.orgNumber)!,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                    Text(detail.phone,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              _statusBadge(detail),
              const SizedBox(width: AppSpacing.md),
              Text('Registered ${detail.createdAt.split('T').first}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _resetPin(detail),
                icon: const Icon(Icons.password, size: 16),
                label: const Text('Reset PIN'),
              ),
              if (detail.isJobPostingBlocked)
                OutlinedButton.icon(
                  onPressed: () => _unblock(detail, 'job_posting'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
                  icon: const Icon(Icons.lock_open, size: 16),
                  label: const Text('Unblock Posting'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _showBlockDialog(detail, 'job_posting'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Block Posting'),
                ),
              if (detail.isActive)
                OutlinedButton.icon(
                  onPressed: () => _showBlockDialog(detail, 'full'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.person_off, size: 16),
                  label: const Text('Block Profile'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _unblock(detail, 'full'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
                  icon: const Icon(Icons.lock_open, size: 16),
                  label: const Text('Unblock'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.local_hospital, size: 18, color: AppColors.primaryDark),
                        SizedBox(width: AppSpacing.xs),
                        Text('Profile', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (!_editMode)
                      TextButton.icon(
                        onPressed: () => _enterEditMode(detail),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_editMode)
                  _buildEditForm(detail)
                else
                  _buildReadOnly(detail),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildNotesSection(detail),
          const SizedBox(height: AppSpacing.lg),
          _buildAuditPreview(),
        ],
      ),
    );
  }

  Widget _statusBadge(AdminOrganisationListItem detail) {
    if (!detail.isActive) {
      return const _StatusPill(icon: Icons.block, color: AppColors.error, label: 'Blocked');
    }
    if (detail.isJobPostingBlocked) {
      return const _StatusPill(icon: Icons.block, color: AppColors.error, label: 'Posting Blocked');
    }
    return const _StatusPill(icon: Icons.check_circle, color: AppColors.success, label: 'Active');
  }

  Widget _buildReadOnly(AdminOrganisationListItem detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(Icons.local_hospital, 'Organisation Name', detail.organisationName),
        _field(Icons.badge, 'Contact Person', detail.fullName),
        _field(Icons.phone, 'Phone', detail.phone),
        _field(
            Icons.category,
            'Type',
            OrganisationType.displayNames[detail.organisationType] ??
                detail.organisationType),
        _field(Icons.location_city, 'City', City.displayNames[detail.city] ?? detail.city),
        _field(Icons.location_on, 'Area', detail.area),
        if (detail.blockReason != null)
          _field(Icons.report_outlined, 'Block Reason', detail.blockReason!),
      ],
    );
  }

  Widget _buildEditForm(AdminOrganisationListItem detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _organisationNameController,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.local_hospital),
              labelText: 'Organisation Name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _fullNameController,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge),
              labelText: 'Contact Person', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.phone),
            labelText: 'Phone',
            helperText: 'Same account, same profile/requirements — this only changes the login number.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _editOrganisationType,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category),
              labelText: 'Type', border: OutlineInputBorder()),
          items: OrganisationType.all
              .map((t) => DropdownMenuItem(
                  value: t, child: Text(OrganisationType.displayNames[t] ?? t)))
              .toList(),
          onChanged: (value) => setState(() => _editOrganisationType = value),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _editCity,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.location_city),
              labelText: 'City', border: OutlineInputBorder()),
          items: [
            ...City.all.map((c) => DropdownMenuItem(
                value: c, child: Text(City.displayNames[c] ?? c))),
            const DropdownMenuItem(
                value: _organisationCityOthers, child: Text('Others')),
          ],
          onChanged: (value) => setState(() => _editCity = value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _areaController,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.location_on),
              labelText: 'Area', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _savingEdits ? null : () => _saveEdits(detail),
              icon: _savingEdits
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check, size: 16),
              label: const Text('Save Changes'),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed:
                  _savingEdits ? null : () => setState(() => _editMode = false),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: AppSpacing.xs),
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 13, color: AppColors.primaryDark),
          ),
          SizedBox(
              width: 118,
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Admin-only personal/internal note about this organisation account —
  /// never shown to the organisation's own self-view. Mirrors
  /// IndividualDetailScreen's own Notes section exactly.
  Widget _buildNotesSection(AdminOrganisationListItem detail) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.sticky_note_2_outlined, size: 18, color: AppColors.primaryDark),
                  SizedBox(width: AppSpacing.xs),
                  Text('Notes', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                ],
              ),
              if (!_editingNotes)
                TextButton.icon(
                  onPressed: () => _enterEditNotes(detail),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_editingNotes)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Internal notes about this organisation account (never shown to them)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _savingNotes ? null : () => _saveNotes(detail),
                      icon: _savingNotes
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Save Notes'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: _savingNotes ? null : () => setState(() => _editingNotes = false),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            )
          else
            Text(
              detail.notes?.isNotEmpty == true ? detail.notes! : 'No notes yet.',
              style: TextStyle(
                color: detail.notes?.isNotEmpty == true ? null : AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history, size: 18, color: AppColors.primaryDark),
                  SizedBox(width: AppSpacing.xs),
                  Text('Audit History', style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.bold)),
                ],
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamed('/audit-logs', arguments: widget.userId),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View full audit log'),
              ),
            ],
          ),
          ScopedAuditHistorySection(
            targetUserId: widget.userId,
            itemBuilder: _buildAuditEntryRow,
          ),
        ],
      ),
    );
  }

  Widget _buildAuditEntryRow(BuildContext context, AuditLogEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: Text(
                    entry.createdAt.replaceFirst('T', ' ').split('.').first,
                    style: const TextStyle(
                        fontSize: AppTypography.small, color: AppColors.textSecondary)),
              ),
              SizedBox(width: 160, child: Text(entry.action)),
              Expanded(
                child: Text(
                  entry.afterValue != null ? formatAuditValue(entry.afterValue) : '-',
                  style: const TextStyle(fontSize: AppTypography.small),
                ),
              ),
            ],
          ),
          if (entry.jobId != null || entry.requirementNumber != null || entry.targetUserName != null)
            Padding(
              padding: const EdgeInsets.only(left: 160, top: 2),
              child: Wrap(
                spacing: AppSpacing.lg,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  if (entry.jobId != null || entry.requirementNumber != null)
                    buildJobOrRequirementCell(context, entry),
                  if (entry.targetUserName != null) buildTargetCell(context, entry),
                ],
              ),
            ),
          if (buildAuditReasonLine(entry) != null)
            Padding(
              padding: const EdgeInsets.only(left: 160, top: 2),
              child: buildAuditReasonLine(entry)!,
            ),
        ],
      ),
    );
  }
}

/// A color-coded status pill with an icon — the account's active/blocked
/// state read at a glance, not just from the word alone.
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _StatusPill({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
