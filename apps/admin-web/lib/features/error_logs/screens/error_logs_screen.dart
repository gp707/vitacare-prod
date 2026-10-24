import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_error_logs_repository.dart';

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

/// "5 min ago" / "3 h ago" / "2 d ago".
String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

String _agoFromIso(String iso) {
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _ago(parsed.toLocal());
}

/// Opens the account's own detail screen — same per-role routing as
/// TicketsScreen._openAccount. Does nothing for an admin/super_admin (no
/// detail screen for those) or an unauthenticated request (no user at all).
void _openAccount(BuildContext context, {required String? role, required String? userId, String? caregiverProfileId}) {
  switch (role) {
    case 'caregiver':
      if (caregiverProfileId != null) {
        Navigator.of(context).pushNamed('/caregiver-detail', arguments: caregiverProfileId);
      }
      break;
    case 'individual':
      Navigator.of(context).pushNamed('/individual-detail', arguments: userId);
      break;
    case 'organisation':
      Navigator.of(context).pushNamed('/organisation-detail', arguments: userId);
      break;
  }
}

/// Asks for an optional note, then returns it (empty string = no note), or
/// null if the admin cancelled.
Future<String?> _askResolutionNote(BuildContext context, {required String title, required String confirmLabel}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What was done? (optional)',
            hintText: 'e.g. Called, asked them to update the app and retry',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: Text(confirmLabel)),
      ],
    ),
  );
}

/// Backend health and who it hurt. Every genuinely unexpected server error
/// (never an already-categorized AUTH_/GEN_/JOB_-coded one — see
/// GlobalExceptionFilter on the backend), kept for a rolling 7 days, with
/// the real request data behind it and the person it happened to — so an
/// admin can call them — plus an open/resolved workflow so handled errors
/// stop looking like work to do.
class ErrorLogsScreen extends ConsumerStatefulWidget {
  const ErrorLogsScreen({super.key});

  @override
  ConsumerState<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends ConsumerState<ErrorLogsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<AdminDailyRequestStats> _stats = [];
  String? _statsError;

  // Shared between the tabs: "View errors" on an affected person switches to
  // the Errors tab already narrowed to that person.
  String? _filterUserId;
  String? _filterUserLabel;
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ref.read(adminErrorLogsRepositoryProvider).getStats(days: 7);
      if (mounted) {
        setState(() {
          _stats = stats;
          _statsError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _statsError = e.message);
    }
  }

  void _showErrorsFor(AffectedUser user) {
    setState(() {
      _filterUserId = user.userId;
      _filterUserLabel = [if (user.displayId != null) user.displayId!, user.fullName].join(' · ');
    });
    _tabs.animateTo(0);
  }

  void _clearUserFilter() => setState(() {
        _filterUserId = null;
        _filterUserLabel = null;
      });

  /// Something was resolved on either tab — both lists must refresh.
  void _onChanged() => setState(() => _reloadToken++);

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
                'Every unexpected backend error (not a normal validation/business rejection), kept for 7 days. '
                'Open one to see what the person was doing; call or WhatsApp them from here, then mark it resolved.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_statsError != null)
                Text(_statsError!, style: const TextStyle(color: AppColors.error))
              else
                _buildStats(),
              const SizedBox(height: AppSpacing.md),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [Tab(text: 'Errors'), Tab(text: 'Affected users')],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ErrorsTab(
                      userId: _filterUserId,
                      userLabel: _filterUserLabel,
                      onClearUser: _clearUserFilter,
                      reloadToken: _reloadToken,
                      onChanged: _onChanged,
                    ),
                    _AffectedUsersTab(
                      reloadToken: _reloadToken,
                      onChanged: _onChanged,
                      onViewErrors: _showErrorsFor,
                    ),
                  ],
                ),
              ),
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
        _StatCard(label: 'Today', requests: today?.totalRequests ?? 0, errors: today?.totalErrors ?? 0),
        _StatCard(label: 'Last 7 days', requests: weekRequests, errors: weekErrors),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Errors tab
// ---------------------------------------------------------------------------

class _ErrorsTab extends ConsumerStatefulWidget {
  final String? userId;
  final String? userLabel;
  final VoidCallback onClearUser;
  final int reloadToken;
  final VoidCallback onChanged;

  const _ErrorsTab({
    required this.userId,
    required this.userLabel,
    required this.onClearUser,
    required this.reloadToken,
    required this.onChanged,
  });

  @override
  ConsumerState<_ErrorsTab> createState() => _ErrorsTabState();
}

class _ErrorsTabState extends ConsumerState<_ErrorsTab> with AutomaticKeepAliveClientMixin {
  int _page = 1;
  String _status = 'open';
  final _searchController = TextEditingController();
  String _search = '';
  List<AdminErrorLogItem> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ErrorsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.reloadToken != widget.reloadToken) {
      _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(adminErrorLogsRepositoryProvider).list(
            page: _page,
            status: _status,
            userId: widget.userId,
            search: _search,
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

  Future<void> _resolve(AdminErrorLogItem item) async {
    final note = await _askResolutionNote(context, title: 'Mark this error resolved', confirmLabel: 'Mark resolved');
    if (note == null) return;
    try {
      await ref.read(adminErrorLogsRepositoryProvider).resolve(item.id, note: note);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showVitaErrorBanner(context, e.message);
    }
  }

  /// Short "who" summary for the list view — the dialog shows the fuller
  /// version.
  String _customerSummary(AdminErrorLogItem item) {
    if (item.userId == null) return '-';
    return [
      if (item.userDisplayId != null) item.userDisplayId!,
      item.userFullName ?? _roleLabel(item.userRole),
    ].join(' · ');
  }

  void _showDetail(AdminErrorLogItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ErrorDetailDialog(
        item: item,
        onOpenAccount: () => _openAccount(
          context,
          role: item.userRole,
          userId: item.userId,
          caregiverProfileId: item.caregiverProfileId,
        ),
        onResolve: item.isResolved ? null : () => _resolve(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'open', label: Text('Open')),
                  ButtonSegment(value: 'resolved', label: Text('Resolved')),
                  ButtonSegment(value: 'all', label: Text('All')),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  _status = s.first;
                  _page = 1;
                  _load();
                },
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search path or message',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _search = '';
                              _page = 1;
                              _load();
                            },
                          ),
                  ),
                  onSubmitted: (value) {
                    _search = value.trim();
                    _page = 1;
                    _load();
                  },
                ),
              ),
              if (widget.userId != null)
                InputChip(
                  label: Text('Only ${widget.userLabel ?? 'this person'}'),
                  onDeleted: widget.onClearUser,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Expanded(child: Center(child: VitaLoadingIndicator()))
          else if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
          else ...[
            Expanded(child: _buildList()),
            if (_meta != null) _Pager(meta: _meta!, onPage: (p) {
              _page = p;
              _load();
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _status == 'open' ? 'No open errors. Nothing needs attention.' : 'No errors match this filter.',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text('${item.method} ${item.path}'),
            trailing: _StatusChip(resolved: item.isResolved),
            onTap: () => _showDetail(item),
            fields: [
              VitaListCard.kv('Time', _agoFromIso(item.createdAt)),
              VitaListCard.kv('Customer', _customerSummary(item)),
              if (item.userPhone != null) VitaListCard.kv('Phone', item.userPhone!),
              VitaListCard.kv('Message', item.message),
            ],
            actions: [
              if (item.hasCustomer) ContactButtons(phone: item.userPhone!),
              if (!item.isResolved) TextButton(onPressed: () => _resolve(item), child: const Text('Resolve')),
            ],
          );
        },
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Request')),
            DataColumn(label: Text('Message')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _items
              .map((item) => DataRow(
                    onSelectChanged: (_) => _showDetail(item),
                    cells: [
                      DataCell(Text(_agoFromIso(item.createdAt))),
                      DataCell(Text(_customerSummary(item))),
                      DataCell(Text(item.userPhone ?? '-')),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text('${item.method} ${item.path}', overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(item.message, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(_StatusChip(resolved: item.isResolved)),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.hasCustomer) ContactButtons(phone: item.userPhone!),
                          if (!item.isResolved)
                            TextButton(onPressed: () => _resolve(item), child: const Text('Resolve')),
                        ],
                      )),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Affected users tab
// ---------------------------------------------------------------------------

class _AffectedUsersTab extends ConsumerStatefulWidget {
  final int reloadToken;
  final VoidCallback onChanged;
  final ValueChanged<AffectedUser> onViewErrors;

  const _AffectedUsersTab({required this.reloadToken, required this.onChanged, required this.onViewErrors});

  @override
  ConsumerState<_AffectedUsersTab> createState() => _AffectedUsersTabState();
}

class _AffectedUsersTabState extends ConsumerState<_AffectedUsersTab> with AutomaticKeepAliveClientMixin {
  int _page = 1;
  String _status = 'open';
  List<AffectedUser> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AffectedUsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _page = 1;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(adminErrorLogsRepositoryProvider).listAffectedUsers(page: _page, status: _status);
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

  Future<void> _markContacted(AffectedUser user) async {
    final note = await _askResolutionNote(
      context,
      title: 'Resolve all open errors for ${user.fullName}',
      confirmLabel: 'Mark contacted & resolved',
    );
    if (note == null) return;
    try {
      final count = await ref.read(adminErrorLogsRepositoryProvider).resolveAllForUser(user.userId, note: note);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Resolved $count error${count == 1 ? '' : 's'} for ${user.fullName}.')));
      }
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showVitaErrorBanner(context, e.message);
    }
  }

  String _who(AffectedUser u) => [if (u.displayId != null) u.displayId!, u.fullName].join(' · ');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'open', label: Text('With open errors')),
                  ButtonSegment(value: 'all', label: Text('Everyone affected')),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  _status = s.first;
                  _page = 1;
                  _load();
                },
              ),
              const Text(
                'People who hit an error while signed in — most recent first. Errors before login can\'t be tied to a person.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Expanded(child: Center(child: VitaLoadingIndicator()))
          else if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
          else ...[
            Expanded(child: _buildList()),
            if (_meta != null) _Pager(meta: _meta!, onPage: (p) {
              _page = p;
              _load();
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return const Center(child: Text('Nobody to follow up with — no one has open errors.'));
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final user = _items[index];
          return VitaListCard(
            title: Text(_who(user)),
            onTap: () => widget.onViewErrors(user),
            fields: [
              VitaListCard.kv('Type', _roleLabel(user.role)),
              VitaListCard.kv('Phone', user.phone),
              VitaListCard.kv('Errors', '${user.openCount} open / ${user.errorCount} total'),
              VitaListCard.kv('Last error', '${_ago(user.lastErrorAt.toLocal())} · ${user.lastRequest}'),
              VitaListCard.kv('Message', user.lastMessage),
            ],
            actions: [
              ContactButtons(phone: user.phone),
              TextButton(onPressed: () => widget.onViewErrors(user), child: const Text('View errors')),
              if (user.openCount > 0)
                TextButton(onPressed: () => _markContacted(user), child: const Text('Mark contacted')),
            ],
          );
        },
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Errors'), numeric: true),
            DataColumn(label: Text('Last error')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _items
              .map((user) => DataRow(
                    onSelectChanged: (_) => widget.onViewErrors(user),
                    cells: [
                      DataCell(Text(_who(user))),
                      DataCell(Text(_roleLabel(user.role))),
                      DataCell(Text(user.phone)),
                      DataCell(Text('${user.openCount} open / ${user.errorCount}')),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Text(
                          '${_ago(user.lastErrorAt.toLocal())} · ${user.lastRequest}\n${user.lastMessage}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      )),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ContactButtons(phone: user.phone),
                          TextButton(onPressed: () => widget.onViewErrors(user), child: const Text('View errors')),
                          if (user.openCount > 0)
                            TextButton(onPressed: () => _markContacted(user), child: const Text('Mark contacted')),
                        ],
                      )),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail dialog
// ---------------------------------------------------------------------------

class _ErrorDetailDialog extends StatelessWidget {
  final AdminErrorLogItem item;
  final VoidCallback onOpenAccount;
  final VoidCallback? onResolve;

  const _ErrorDetailDialog({required this.item, required this.onOpenAccount, required this.onResolve});

  String get _prettyContext => const JsonEncoder.withIndent('  ').convert(item.requestContext);

  @override
  Widget build(BuildContext context) {
    final hasOpenableAccount = item.userId != null &&
        (item.userRole == 'caregiver' || item.userRole == 'individual' || item.userRole == 'organisation');
    return AlertDialog(
      title: Text('${item.method} ${item.path}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('Time', '${item.createdAt} (${_agoFromIso(item.createdAt)})'),
              _DetailRow('Status', item.statusCode.toString()),
              if (item.userId != null) ...[
                const SizedBox(height: AppSpacing.xs),
                const Text('Who it happened to', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                InkWell(
                  onTap: hasOpenableAccount
                      ? () {
                          Navigator.of(context).pop();
                          onOpenAccount();
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
                if (item.userPhone != null) ContactButtons(phone: item.userPhone!),
              ] else
                const _DetailRow('Customer', 'Unauthenticated request — no account yet'),
              if (item.ipAddress != null) _DetailRow('IP', item.ipAddress!),
              if (item.userAgent != null) _DetailRow('Client', item.userAgent!),
              const SizedBox(height: AppSpacing.sm),
              const Text('Message', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(item.message),
              const SizedBox(height: AppSpacing.sm),
              const Text('What they were doing (request data)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text(
                'PINs, codes, passwords and tokens are never stored — they show as [redacted].',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (item.requestContext == null)
                const Text('No request data was captured for this error.',
                    style: TextStyle(color: AppColors.textSecondary))
              else
                _CodeBlock(_prettyContext),
              if (item.stack != null) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('Stack trace', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                _CodeBlock(item.stack!),
              ],
              if (item.isResolved) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('Resolved', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                _DetailRow('By', item.resolvedByName ?? '-'),
                if (item.resolvedAt != null) _DetailRow('When', item.resolvedAt!),
                if (item.resolutionNote != null && item.resolutionNote!.isNotEmpty)
                  _DetailRow('Note', item.resolutionNote!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (onResolve != null)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onResolve!();
            },
            child: const Text('Mark resolved'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _Pager extends StatelessWidget {
  final PaginationMeta meta;
  final ValueChanged<int> onPage;

  const _Pager({required this.meta, required this.onPage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Page ${meta.page} of ${meta.totalPages == 0 ? 1 : meta.totalPages} (${meta.total} total)'),
          IconButton(
            onPressed: meta.page > 1 ? () => onPage(meta.page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: meta.page < meta.totalPages ? () => onPage(meta.page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;

  const _CodeBlock(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: AppTypography.small),
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

class _StatusChip extends StatelessWidget {
  final bool resolved;

  const _StatusChip({required this.resolved});

  @override
  Widget build(BuildContext context) {
    final color = resolved ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        resolved ? 'Resolved' : 'Open',
        style: TextStyle(color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600),
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
