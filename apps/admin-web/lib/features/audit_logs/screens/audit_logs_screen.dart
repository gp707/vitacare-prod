import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/audit_log_models.dart';
import '../data/audit_logs_repository.dart';

/// Renders a JSON value map as a compact "key: value, key: value" string —
/// enough to see what changed at a glance without a full diff-viewer widget.
String formatAuditValue(Map<String, dynamic>? value) {
  if (value == null || value.isEmpty) return '-';
  return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
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
          columns: const [
            DataColumn(label: Text('Timestamp')),
            DataColumn(label: Text('Actor')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Entity')),
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
                    DataCell(Text(entry.targetUserName ?? '-')),
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
