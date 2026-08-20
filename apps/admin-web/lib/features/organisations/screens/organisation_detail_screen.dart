import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../audit_logs/data/audit_log_models.dart';
import '../../audit_logs/data/audit_logs_repository.dart';
import '../../audit_logs/screens/audit_logs_screen.dart' show formatAuditValue;
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

  List<AuditLogEntry> _auditEntries = [];
  bool _auditLoading = true;

  bool _editMode = false;
  bool _savingEdits = false;
  final _fullNameController = TextEditingController();
  final _organisationNameController = TextEditingController();
  final _areaController = TextEditingController();
  String? _editOrganisationType;
  String? _editCity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _organisationNameController.dispose();
    _areaController.dispose();
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
      // Non-critical: the rest of the page still works without this preview.
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  void _enterEditMode(AdminOrganisationListItem detail) {
    _fullNameController.text = detail.fullName;
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
                            fontSize: 22, fontWeight: FontWeight.bold)),
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
                    const Text('Profile',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    if (!_editMode)
                      TextButton(
                          onPressed: () => _enterEditMode(detail),
                          child: const Text('Edit')),
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
          _buildAuditPreview(),
        ],
      ),
    );
  }

  Widget _statusBadge(AdminOrganisationListItem detail) {
    if (!detail.isActive) {
      return const Text('Blocked',
          style:
              TextStyle(color: AppColors.error, fontWeight: FontWeight.bold));
    }
    if (detail.isJobPostingBlocked) {
      return const Text('Posting Blocked',
          style:
              TextStyle(color: AppColors.error, fontWeight: FontWeight.bold));
    }
    return const Text('Active',
        style:
            TextStyle(color: AppColors.success, fontWeight: FontWeight.bold));
  }

  Widget _buildReadOnly(AdminOrganisationListItem detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Organisation Name', detail.organisationName),
        _field('Contact Person', detail.fullName),
        _field('Phone', detail.phone),
        _field(
            'Type',
            OrganisationType.displayNames[detail.organisationType] ??
                detail.organisationType),
        _field('City', City.displayNames[detail.city] ?? detail.city),
        _field('Area', detail.area),
        if (detail.blockReason != null)
          _field('Block Reason', detail.blockReason!),
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
              labelText: 'Organisation Name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _fullNameController,
          decoration: const InputDecoration(
              labelText: 'Contact Person', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _editOrganisationType,
          decoration: const InputDecoration(
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
              labelText: 'Area', border: OutlineInputBorder()),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            ElevatedButton(
              onPressed: _savingEdits ? null : () => _saveEdits(detail),
              child: _savingEdits
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes'),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed:
                  _savingEdits ? null : () => setState(() => _editMode = false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 140,
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(value)),
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
              const Text('Audit History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .pushNamed('/audit-logs', arguments: widget.userId),
                child: const Text('View full audit log'),
              ),
            ],
          ),
          if (_auditLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: VitaLoadingIndicator()),
            )
          else if (_auditEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('No actions recorded for this account yet.'),
            )
          else
            ..._auditEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(
                          entry.createdAt
                              .replaceFirst('T', ' ')
                              .split('.')
                              .first,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                    SizedBox(width: 160, child: Text(entry.action)),
                    Expanded(
                      child: Text(
                        entry.afterValue != null
                            ? formatAuditValue(entry.afterValue)
                            : '-',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
