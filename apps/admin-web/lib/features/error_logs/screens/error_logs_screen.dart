import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_error_logs_repository.dart';

/// Backend health, start-simple version: every genuinely unexpected server
/// error (never an already-categorized AUTH_/GEN_/JOB_-coded one — see
/// GlobalExceptionFilter on the backend) plus a daily request/error count,
/// kept for a rolling 7 days (ErrorLogsService.purgeExpiredLogs).
class ErrorLogsScreen extends ConsumerStatefulWidget {
  const ErrorLogsScreen({super.key});

  @override
  ConsumerState<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends ConsumerState<ErrorLogsScreen> {
  int _page = 1;
  List<AdminErrorLogItem> _items = [];
  PaginationMeta? _meta;
  List<AdminDailyRequestStats> _stats = [];
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
      final repo = ref.read(adminErrorLogsRepositoryProvider);
      final results = await Future.wait([
        repo.list(page: _page),
        repo.getStats(days: 7),
      ]);
      if (mounted) {
        setState(() {
          final listResult = results[0] as AdminErrorLogsListResult;
          _items = listResult.items;
          _meta = listResult.meta;
          _stats = results[1] as List<AdminDailyRequestStats>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Opens the account's own detail screen — same per-role routing as
  /// TicketsScreen._openAccount. Does nothing for an admin/super_admin
  /// (no detail screen for those) or an unauthenticated request (no user
  /// at all).
  void _openAccount(AdminErrorLogItem item) {
    switch (item.userRole) {
      case 'caregiver':
        if (item.caregiverProfileId != null) {
          Navigator.of(context).pushNamed('/caregiver-detail', arguments: item.caregiverProfileId);
        }
        break;
      case 'individual':
        Navigator.of(context).pushNamed('/individual-detail', arguments: item.userId);
        break;
      case 'organisation':
        Navigator.of(context).pushNamed('/organisation-detail', arguments: item.userId);
        break;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'caregiver':
        return 'Caregiver';
      case 'individual':
        return 'Patient/Family';
      case 'organisation':
        return 'Organisation';
      case 'admin':
      case 'super_admin':
        return 'Admin';
      default:
        return role ?? 'Unknown';
    }
  }

  void _showDetail(AdminErrorLogItem item) {
    final hasOpenableAccount = item.userId != null &&
        (item.userRole == 'caregiver' || item.userRole == 'individual' || item.userRole == 'organisation');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.method} ${item.path}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow('Time', item.createdAt),
                _DetailRow('Status', item.statusCode.toString()),
                if (item.userId != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const Text('Customer', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xs),
                  InkWell(
                    onTap: hasOpenableAccount
                        ? () {
                            Navigator.of(context).pop();
                            _openAccount(item);
                          }
                        : null,
                    child: Text(
                      [
                        if (item.userDisplayId != null) item.userDisplayId!,
                        if (item.userFullName != null) item.userFullName!,
                        _roleLabel(item.userRole),
                        if (item.userPhone != null) item.userPhone!,
                      ].join(' · '),
                      style: TextStyle(
                        color: hasOpenableAccount ? AppColors.primary : null,
                        decoration: hasOpenableAccount ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ] else
                  const _DetailRow('Customer', 'Unauthenticated request — no account yet'),
                if (item.ipAddress != null) _DetailRow('IP', item.ipAddress!),
                const SizedBox(height: AppSpacing.sm),
                const Text('Message', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(item.message),
                if (item.stack != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Stack trace', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppSpacing.xs),
                    ),
                    child: SelectableText(
                      item.stack!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: AppTypography.small),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.errorLogs,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Error Logs',
                  style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Every unexpected backend error (not a normal validation/business rejection), kept for 7 days.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else ...[
                _buildStats(),
                const SizedBox(height: AppSpacing.md),
                Expanded(child: _buildList()),
                if (_meta != null) _buildPager(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    final today = _stats.isNotEmpty ? _stats.last : null;
    final weekRequests = _stats.fold<int>(0, (sum, s) => sum + s.totalRequests);
    final weekErrors = _stats.fold<int>(0, (sum, s) => sum + s.totalErrors);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _StatCard(
          label: 'Today',
          requests: today?.totalRequests ?? 0,
          errors: today?.totalErrors ?? 0,
        ),
        _StatCard(
          label: 'Last 7 days',
          requests: weekRequests,
          errors: weekErrors,
        ),
      ],
    );
  }

  /// Short "who" summary for the list view — the dialog shows the fuller
  /// version. Falls back to the bare role (or '-' for an unauthenticated
  /// request) when a display id/name isn't resolvable (e.g. an admin, who
  /// has no caregiver/individual/organisation profile to join against).
  String _customerSummary(AdminErrorLogItem item) {
    if (item.userId == null) return '-';
    return item.userDisplayId ?? item.userFullName ?? _roleLabel(item.userRole);
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return const Center(child: Text('No errors in the last 7 days.'));
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text('${item.method} ${item.path}'),
            trailing: _StatusCodeChip(statusCode: item.statusCode),
            onTap: () => _showDetail(item),
            fields: [
              VitaListCard.kv('Time', item.createdAt),
              VitaListCard.kv('Customer', _customerSummary(item)),
              VitaListCard.kv('Message', item.message),
            ],
          );
        },
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Path')),
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Message')),
          ],
          rows: _items
              .map((item) => DataRow(cells: [
                    DataCell(Text(item.createdAt), onTap: () => _showDetail(item)),
                    DataCell(Text(item.method), onTap: () => _showDetail(item)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(item.path, overflow: TextOverflow.ellipsis),
                      ),
                      onTap: () => _showDetail(item),
                    ),
                    DataCell(Text(_customerSummary(item)), onTap: () => _showDetail(item)),
                    DataCell(_StatusCodeChip(statusCode: item.statusCode)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Text(item.message, overflow: TextOverflow.ellipsis),
                      ),
                      onTap: () => _showDetail(item),
                    ),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPager() {
    final meta = _meta!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
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

class _StatCard extends StatelessWidget {
  final String label;
  final int requests;
  final int errors;

  const _StatCard({required this.label, required this.requests, required this.errors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      constraints: const BoxConstraints(minWidth: 200),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          Text('$requests requests',
              style: const TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold)),
          Text(
            '$errors error${errors == 1 ? '' : 's'}',
            style: TextStyle(color: errors > 0 ? AppColors.error : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatusCodeChip extends StatelessWidget {
  final int statusCode;

  const _StatusCodeChip({required this.statusCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        statusCode.toString(),
        style: const TextStyle(color: AppColors.error, fontSize: AppTypography.small, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
