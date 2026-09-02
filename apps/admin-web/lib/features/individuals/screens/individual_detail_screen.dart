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
import '../../jobs/screens/admin_jobs_screen.dart' show JobsScreenInitialFilter;
import '../data/admin_individuals_repository.dart';

/// individual_profiles has no profile depth beyond the two block levers —
/// this is deliberately a single-page detail view (no tabs, unlike
/// CaregiverDetailScreen), just identity + block status + an edit form for
/// the one editable field (full_name) + a scoped preview of this
/// account's own audit history with a link to the full log.
class IndividualDetailScreen extends ConsumerStatefulWidget {
  final String userId;

  const IndividualDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<IndividualDetailScreen> createState() =>
      _IndividualDetailScreenState();
}

class _IndividualDetailScreenState
    extends ConsumerState<IndividualDetailScreen> {
  AdminIndividualListItem? _detail;
  bool _loading = true;
  String? _errorMessage;

  List<AuditLogEntry> _auditEntries = [];
  bool _auditLoading = true;

  bool _editMode = false;
  bool _savingEdits = false;
  final _fullNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final detail = await ref
          .read(adminIndividualsRepositoryProvider)
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

  void _enterEditMode(AdminIndividualListItem detail) {
    _fullNameController.text = detail.fullName;
    setState(() => _editMode = true);
  }

  Future<void> _saveEdits(AdminIndividualListItem detail) async {
    setState(() => _savingEdits = true);
    try {
      final fields = <String, dynamic>{};
      final fullName = _fullNameController.text.trim();
      if (fullName.isNotEmpty && fullName != detail.fullName) {
        fields['full_name'] = fullName;
      }

      if (fields.isNotEmpty) {
        await ref
            .read(adminIndividualsRepositoryProvider)
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

  /// Same redirect as IndividualsListScreen's own "View Jobs" row action —
  /// the merged Jobs tab, pre-filtered to just this individual's own
  /// postings (every other Jobs filter stays available to narrow further).
  void _viewJobs(AdminIndividualListItem detail) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/jobs',
      (route) => false,
      arguments: JobsScreenInitialFilter(
        postedByUserId: detail.userId,
        postedByLabel: detail.fullName,
      ),
    );
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
      current: AppShellSection.patientsFamily,
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
                    Text(detail.fullName,
                        style: const TextStyle(
                            fontSize: AppTypography.heading, fontWeight: FontWeight.bold)),
                    if (patientDisplayId(detail.patientNumber) != null)
                      Text(patientDisplayId(detail.patientNumber)!,
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
          OutlinedButton.icon(
            onPressed: () => _viewJobs(detail),
            icon: const Icon(Icons.work_outline, size: 16),
            label: const Text('View Jobs Posted'),
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
                        Icon(Icons.person, size: 18, color: AppColors.primaryDark),
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
          _buildAuditPreview(),
        ],
      ),
    );
  }

  Widget _statusBadge(AdminIndividualListItem detail) {
    if (!detail.isActive) {
      return const _StatusPill(icon: Icons.block, color: AppColors.error, label: 'Blocked');
    }
    if (detail.isJobPostingBlocked) {
      return const _StatusPill(icon: Icons.block, color: AppColors.error, label: 'Posting Blocked');
    }
    return const _StatusPill(icon: Icons.check_circle, color: AppColors.success, label: 'Active');
  }

  Widget _buildReadOnly(AdminIndividualListItem detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(Icons.badge, 'Full Name', detail.fullName),
        _field(Icons.phone, 'Phone', detail.phone),
        if (detail.blockReason != null)
          _field(Icons.report_outlined, 'Block Reason', detail.blockReason!),
      ],
    );
  }

  Widget _buildEditForm(AdminIndividualListItem detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _fullNameController,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge),
              labelText: 'Full Name', border: OutlineInputBorder()),
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
                              fontSize: AppTypography.small, color: AppColors.textSecondary)),
                    ),
                    SizedBox(width: 160, child: Text(entry.action)),
                    Expanded(
                      child: Text(
                        entry.afterValue != null
                            ? formatAuditValue(entry.afterValue)
                            : '-',
                        style: const TextStyle(fontSize: AppTypography.small),
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
