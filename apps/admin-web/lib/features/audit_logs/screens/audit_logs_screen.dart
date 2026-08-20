import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/audit_log_models.dart';
import '../data/audit_logs_repository.dart';
import '../../jobs/widgets/job_detail_dialog.dart';

/// Renders a JSON value map as a compact "key: value, key: value" string —
/// enough to see what changed at a glance without a full diff-viewer widget.
String formatAuditValue(Map<String, dynamic>? value) {
  if (value == null || value.isEmpty) return '-';
  return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
}

/// Same convention as the shared jobDisplayId() helper — kept as a local
/// equivalent since AuditLogEntry only carries the two raw resolved
/// numbers, not a full JobModel. Only called once entry.jobId is known
/// non-null (see the DataCell above), so exactly one of
/// adminJobNumber/patientJobNumber is always set here.
String _auditJobDisplayId(AuditLogEntry entry) {
  if (entry.adminJobNumber != null) return 'ADMIN-JOB-${entry.adminJobNumber}';
  if (entry.patientJobNumber != null) return 'PAT-JOB-${entry.patientJobNumber}';
  return 'JOB-${entry.jobNumber}';
}

/// Same convention as organisationJobDisplayId() from the shared package —
/// kept local since AuditLogEntry only carries the raw resolved number,
/// not a full OrganisationRequirementModel.
String _auditRequirementDisplayId(AuditLogEntry entry) => 'ORG-JOB-${entry.requirementNumber}';

/// The target user's own display id (NUR-/PAT-/ORG-`<n>`), reusing the same
/// helpers every other screen uses — null when there's no target at all,
/// or the target is an admin/super_admin (no display-id convention for
/// those; the raw name is enough).
String? _auditTargetDisplayId(AuditLogEntry entry) {
  switch (entry.targetUserRole) {
    case 'caregiver':
      return caregiverDisplayId(entry.targetCaregiverNumber);
    case 'individual':
      return patientDisplayId(entry.targetPatientNumber);
    case 'organisation':
      return organisationDisplayId(entry.targetOrgNumber);
    default:
      return null;
  }
}

class AuditLogsScreen extends ConsumerStatefulWidget {
  /// Optional pre-filter, used when navigating here from a caregiver's
  /// "view full history" link.
  final String? initialTargetUserId;

  const AuditLogsScreen({super.key, this.initialTargetUserId});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> {
  String? _action;
  DateTime? _fromDate;
  DateTime? _toDate;
  int _page = 1;

  List<AuditLogEntry> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(auditLogsRepositoryProvider).list(
            AuditLogListFilters(
              targetUserId: widget.initialTargetUserId,
              action: _action,
              fromDate: _fromDate?.toIso8601String().split('T').first,
              toDate: _toDate?.toIso8601String().split('T').first,
              page: _page,
            ),
          );
      if (mounted) {
        setState(() {
          _items = result.items;
          _meta = result.meta;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    _page = 1;
    _load();
  }

  void _openJob(String jobId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => JobDetailDialog(jobId: jobId),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      initialDate: (isFrom ? _fromDate : _toDate) ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() => isFrom ? _fromDate = picked : _toDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.auditLogs,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Audit Logs', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.md),
              _buildFilterPanel(),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else
                Expanded(child: _buildTable()),
              if (_meta != null) _buildPager(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'Action', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All actions')),
              ...AuditAction.all.map((a) => DropdownMenuItem<String?>(value: a, child: Text(a))),
            ],
            onChanged: (value) => setState(() => _action = value),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isFrom: true),
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(_fromDate == null ? 'From date' : _fromDate!.toIso8601String().split('T').first),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isFrom: false),
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(_toDate == null ? 'To date' : _toDate!.toIso8601String().split('T').first),
        ),
        ElevatedButton(onPressed: _applyFilters, child: const Text('Apply Filters')),
      ],
    );
  }

  Widget _buildTable() {
    if (_items.isEmpty) {
      return const Center(child: Text('No audit log entries match these filters.'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          // Default fixed row height clips the two-line Job cell (display
          // id + the selectable UUID below it) — give rows room to grow.
          dataRowMinHeight: 56,
          dataRowMaxHeight: 88,
          columns: const [
            DataColumn(label: Text('Timestamp')),
            DataColumn(label: Text('Actor')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Entity')),
            DataColumn(label: Text('Job / Requirement')),
            DataColumn(label: Text('Target')),
            DataColumn(label: Text('Before')),
            DataColumn(label: Text('After')),
            DataColumn(label: Text('IP')),
          ],
          rows: _items
              .map(
                (entry) => DataRow(
                  cells: [
                    DataCell(Text(entry.createdAt.replaceFirst('T', ' ').split('.').first)),
                    DataCell(Text(entry.userName ?? '-')),
                    DataCell(Text(entry.action)),
                    DataCell(Text(entry.entityType)),
                    DataCell(_buildJobOrRequirementCell(entry)),
                    DataCell(_buildTargetCell(entry)),
                    DataCell(SizedBox(width: 220, child: Text(formatAuditValue(entry.beforeValue)))),
                    DataCell(SizedBox(width: 220, child: Text(formatAuditValue(entry.afterValue)))),
                    DataCell(Text(entry.ipAddress ?? '-')),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// Job entries stay clickable (opens JobDetailDialog, unchanged).
  /// Organisation-requirement entries show the same "display id + raw
  /// selectable UUID" shape but aren't clickable — there's no admin-web
  /// dialog that opens a requirement's detail from outside its own list
  /// screen, unlike jobs' JobDetailDialog which is already a standalone
  /// public widget.
  Widget _buildJobOrRequirementCell(AuditLogEntry entry) {
    if (entry.jobNumber != null && entry.jobId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _openJob(entry.jobId!),
            child: Text(_auditJobDisplayId(entry)),
          ),
          // The raw UUID, selectable so it can be copied straight into a
          // DB query or support ticket — the display id alone isn't
          // enough when you need the exact id.
          SelectableText(entry.jobId!, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      );
    }
    if (entry.requirementNumber != null && entry.requirementId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_auditRequirementDisplayId(entry), style: const TextStyle(fontWeight: FontWeight.w600)),
          SelectableText(entry.requirementId!, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      );
    }
    return const Text('-');
  }

  /// Shows the target's own display id (NUR-/PAT-/ORG-`<n>`) above their
  /// name when the target is a caregiver/individual/organisation — an
  /// admin/super_admin target (or no target at all) just shows the name,
  /// same as before.
  Widget _buildTargetCell(AuditLogEntry entry) {
    final displayId = _auditTargetDisplayId(entry);
    if (entry.targetUserName == null) return const Text('-');
    if (displayId == null) return Text(entry.targetUserName!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(displayId, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(entry.targetUserName!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildPager() {
    final meta = _meta!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Page ${meta.page} of ${meta.totalPages} (${meta.total} total)'),
          IconButton(
            onPressed: meta.page > 1
                ? () {
                    _page = meta.page - 1;
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: meta.page < meta.totalPages
                ? () {
                    _page = meta.page + 1;
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
