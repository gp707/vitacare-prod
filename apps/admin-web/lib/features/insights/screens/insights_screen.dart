import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_insights_repository.dart';

const _tabActive = 0;
const _tabNeverCameBack = 2;
const _tabNoAccepted = 3;
const _tabCaregiversNotApplied = 4;

String _roleLabel(String role) {
  switch (role) {
    case 'caregiver':
      return 'Caregiver';
    case 'individual':
      return 'Patient/Family';
    case 'organisation':
      return 'Organisation';
    default:
      return role;
  }
}

/// "5 min ago" / "3 h ago" / "2 d ago".
String _ago(DateTime? time) {
  if (time == null) return '-';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// "23 Oct 18:20" in the admin's own timezone.
String _stamp(DateTime? time) {
  if (time == null) return '-';
  final local = time.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} $hh:$mm';
}

String _who(InsightAccount a) => [if (a.displayId != null) a.displayId!, a.fullName].join(' · ');

/// Opens the account's own detail screen — same per-role routing as
/// TicketsScreen._openAccount / ErrorLogsScreen._openAccount.
void _openAccount(BuildContext context, InsightAccount account) {
  switch (account.role) {
    case 'caregiver':
      if (account.caregiverProfileId != null) {
        Navigator.of(context).pushNamed('/caregiver-detail', arguments: account.caregiverProfileId);
      }
      break;
    case 'individual':
      Navigator.of(context).pushNamed('/individual-detail', arguments: account.userId);
      break;
    case 'organisation':
      Navigator.of(context).pushNamed('/organisation-detail', arguments: account.userId);
      break;
  }
}

/// Who is using the app and how: recent activity, most-used buttons, people
/// who registered and never came back, posters whose applicants were never
/// accepted, and caregivers who never applied. Activity numbers come from
/// `users.last_seen_at`/`app_events` (migration 084) and only fill in as
/// people use a build that reports them.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  InsightsSummary? _summary;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await ref.read(adminInsightsRepositoryProvider).getSummary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _summaryError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _summaryError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.insights,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Insights',
                        style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: 'Refresh counts',
                    onPressed: _loadSummary,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Who is using the app and where people drop off. Activity and button counts start filling in '
                'from the first day a build that reports them is in use.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              _buildSummary(),
              const SizedBox(height: AppSpacing.md),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Active users'),
                  Tab(text: 'Most used buttons'),
                  Tab(text: 'Never came back'),
                  Tab(text: 'No candidate accepted'),
                  Tab(text: 'Caregivers not applied'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: const [
                    _ActiveUsersTab(),
                    _MostUsedTab(),
                    _NeverCameBackTab(),
                    _NoAcceptedTab(),
                    _CaregiversNotAppliedTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    if (_summaryError != null) {
      return Text(_summaryError!, style: const TextStyle(color: AppColors.error));
    }
    final s = _summary;
    Widget card(String label, int? value, int tab, {String? hint}) => _SummaryCard(
          label: label,
          value: value,
          hint: hint,
          onTap: () => _tabs.animateTo(tab),
        );
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        card('Active · last 24 h', s?.activeUsers24h, _tabActive),
        card('Active · last 48 h', s?.activeUsers48h, _tabActive),
        card('Active · last 7 days', s?.activeUsers7d, _tabActive),
        card('Never came back', s?.inactiveSinceRegistration, _tabNeverCameBack, hint: 'registered 24 h+ ago'),
        card('No candidate accepted', s?.postersWithoutAccepted, _tabNoAccepted, hint: 'had applicants'),
        card('Caregivers not applied', s?.caregiversNeverApplied, _tabCaregiversNotApplied, hint: 'never applied'),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int? value;
  final String? hint;
  final VoidCallback onTap;

  const _SummaryCard({required this.label, required this.value, required this.onTap, this.hint});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: const BoxConstraints(minWidth: 170),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
            const SizedBox(height: AppSpacing.xs),
            Text(value?.toString() ?? '…',
                style: const TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
            if (hint != null)
              Text(hint!, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared paged account report
// ---------------------------------------------------------------------------

/// A filter bar + a table (or, on mobile, cards) + a pager, for any report
/// that returns [InsightAccount]s. Reloads from page 1 whenever [reloadKey]
/// changes (i.e. a filter was changed).
class _AccountReport extends StatefulWidget {
  final Future<InsightsPage<InsightAccount>> Function(int page) loader;
  final Object reloadKey;
  final Widget? filters;
  final List<String> columns;
  final List<String> Function(InsightAccount) cells;
  final String emptyText;

  const _AccountReport({
    required this.loader,
    required this.reloadKey,
    required this.columns,
    required this.cells,
    required this.emptyText,
    this.filters,
  });

  @override
  State<_AccountReport> createState() => _AccountReportState();
}

class _AccountReportState extends State<_AccountReport> {
  int _page = 1;
  List<InsightAccount> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AccountReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) {
      _page = 1;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.loader(_page);
      if (mounted) {
        setState(() {
          _items = result.items;
          _meta = result.meta;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.filters != null) ...[widget.filters!, const SizedBox(height: AppSpacing.md)],
          if (_loading)
            const Expanded(child: Center(child: VitaLoadingIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error))
          else ...[
            Expanded(child: _buildBody()),
            if (_meta != null) _buildPager(_meta!),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) return Center(child: Text(widget.emptyText, textAlign: TextAlign.center));
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          final cells = widget.cells(item);
          return VitaListCard(
            title: Text(cells.first),
            onTap: () => _openAccount(context, item),
            fields: [for (var i = 1; i < cells.length; i++) VitaListCard.kv(widget.columns[i], cells[i])],
          );
        },
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: [for (final c in widget.columns) DataColumn(label: Text(c))],
          rows: [
            for (final item in _items)
              DataRow(
                onSelectChanged: (_) => _openAccount(context, item),
                cells: [for (final cell in widget.cells(item)) DataCell(Text(cell))],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPager(PaginationMeta meta) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Page ${meta.page} of ${meta.totalPages == 0 ? 1 : meta.totalPages} (${meta.total} total)'),
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

class _RoleFilter extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _RoleFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: value,
      hint: const Text('All account types'),
      items: const [
        DropdownMenuItem(value: null, child: Text('All account types')),
        DropdownMenuItem(value: 'caregiver', child: Text('Caregivers')),
        DropdownMenuItem(value: 'individual', child: Text('Patients/Family')),
        DropdownMenuItem(value: 'organisation', child: Text('Organisations')),
      ],
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

class _ActiveUsersTab extends ConsumerStatefulWidget {
  const _ActiveUsersTab();

  @override
  ConsumerState<_ActiveUsersTab> createState() => _ActiveUsersTabState();
}

class _ActiveUsersTabState extends ConsumerState<_ActiveUsersTab> with AutomaticKeepAliveClientMixin {
  int _hours = 24;
  String? _role;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _AccountReport(
      reloadKey: '$_hours-$_role',
      loader: (page) =>
          ref.read(adminInsightsRepositoryProvider).listActiveUsers(hours: _hours, role: _role, page: page),
      filters: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 24, label: Text('24 h')),
              ButtonSegment(value: 48, label: Text('48 h')),
              ButtonSegment(value: 168, label: Text('7 days')),
            ],
            selected: {_hours},
            onSelectionChanged: (s) => setState(() => _hours = s.first),
          ),
          _RoleFilter(value: _role, onChanged: (v) => setState(() => _role = v)),
        ],
      ),
      columns: const ['Who', 'Type', 'Phone', 'Last active', 'Registered'],
      cells: (a) => [_who(a), _roleLabel(a.role), a.phone, '${_ago(a.lastSeenAt)} (${_stamp(a.lastSeenAt)})', _stamp(a.createdAt)],
      emptyText: 'Nobody has been active in this window yet.\nActivity is recorded from the first use of this release.',
    );
  }
}

class _NeverCameBackTab extends ConsumerStatefulWidget {
  const _NeverCameBackTab();

  @override
  ConsumerState<_NeverCameBackTab> createState() => _NeverCameBackTabState();
}

class _NeverCameBackTabState extends ConsumerState<_NeverCameBackTab> with AutomaticKeepAliveClientMixin {
  int _minAgeHours = 24;
  String? _role;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _AccountReport(
      reloadKey: '$_minAgeHours-$_role',
      loader: (page) => ref
          .read(adminInsightsRepositoryProvider)
          .listInactiveSinceRegistration(minAgeHours: _minAgeHours, role: _role, page: page),
      filters: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Registered at least'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 24, label: Text('24 h')),
              ButtonSegment(value: 48, label: Text('48 h')),
              ButtonSegment(value: 168, label: Text('7 days')),
            ],
            selected: {_minAgeHours},
            onSelectionChanged: (s) => setState(() => _minAgeHours = s.first),
          ),
          const Text('ago and not seen since'),
          _RoleFilter(value: _role, onChanged: (v) => setState(() => _role = v)),
        ],
      ),
      columns: const ['Who', 'Type', 'Phone', 'Registered', 'Waiting'],
      cells: (a) => [_who(a), _roleLabel(a.role), a.phone, _stamp(a.createdAt), _ago(a.createdAt)],
      emptyText: 'Everyone who registered has used the app since.',
    );
  }
}

class _NoAcceptedTab extends ConsumerWidget {
  const _NoAcceptedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AccountReport(
      reloadKey: 'static',
      loader: (page) => ref.read(adminInsightsRepositoryProvider).listPostersWithoutAccepted(page: page),
      filters: const Text(
        'Patients/families and organisations whose postings received applicants but who have never accepted '
        'one. Longest waiting first. Postings nobody applied to are not listed.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      columns: const ['Who', 'Type', 'Phone', 'Postings', 'Applicants', 'Awaiting decision', 'First applied'],
      cells: (a) => [
        _who(a),
        _roleLabel(a.role),
        a.phone,
        '${a.postings ?? 0}',
        '${a.applicants ?? 0}',
        '${a.pendingApplicants ?? 0}',
        '${_stamp(a.firstAppliedAt)} (${_ago(a.firstAppliedAt)})',
      ],
      emptyText: 'No poster is waiting on a first acceptance.',
    );
  }
}

class _CaregiversNotAppliedTab extends ConsumerWidget {
  const _CaregiversNotAppliedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AccountReport(
      reloadKey: 'static',
      loader: (page) => ref.read(adminInsightsRepositoryProvider).listCaregiversNeverApplied(page: page),
      filters: const Text(
        'Caregivers who registered but have never applied to any job or organisation requirement. '
        'Longest registered first.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      columns: const ['Who', 'Phone', 'Verification', 'Registered', 'Waiting'],
      cells: (a) => [
        _who(a),
        a.phone,
        a.verificationStatus ?? '-',
        _stamp(a.createdAt),
        _ago(a.createdAt),
      ],
      emptyText: 'Every registered caregiver has applied at least once.',
    );
  }
}

class _MostUsedTab extends ConsumerStatefulWidget {
  const _MostUsedTab();

  @override
  ConsumerState<_MostUsedTab> createState() => _MostUsedTabState();
}

class _MostUsedTabState extends ConsumerState<_MostUsedTab> with AutomaticKeepAliveClientMixin {
  String _kind = 'tap';
  int _days = 7;
  String? _flow;
  List<TopActionRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(adminInsightsRepositoryProvider).getTopActions(kind: _kind, days: _days, flow: _flow);
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _flowLabel(String flow) {
    switch (flow) {
      case 'auth':
        return 'Login / registration';
      case 'individual':
        return 'Patient/Family';
      case 'organisation':
        return 'Organisation';
      case 'caregiver':
        return 'Caregiver';
      default:
        return flow;
    }
  }

  /// Taps made before login (login/registration screens) can't be tied to
  /// an account, so they have no countable people — show a dash, not "0".
  String _people(TopActionRow row) => row.uniqueUsers == 0 ? '–' : '${row.uniqueUsers}';

  String _nice(String? value) => value == null ? '-' : value.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isTap = _kind == 'tap';
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
                  ButtonSegment(value: 'tap', label: Text('Buttons')),
                  ButtonSegment(value: 'screen', label: Text('Screens')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) {
                  _kind = s.first;
                  _load();
                },
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Today')),
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 30, label: Text('30 days')),
                ],
                selected: {_days},
                onSelectionChanged: (s) {
                  _days = s.first;
                  _load();
                },
              ),
              DropdownButton<String?>(
                value: _flow,
                items: const [
                  DropdownMenuItem(value: null, child: Text('All flows')),
                  DropdownMenuItem(value: 'auth', child: Text('Login / registration')),
                  DropdownMenuItem(value: 'individual', child: Text('Patient/Family')),
                  DropdownMenuItem(value: 'organisation', child: Text('Organisation')),
                  DropdownMenuItem(value: 'caregiver', child: Text('Caregiver')),
                ],
                onChanged: (v) {
                  _flow = v;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Expanded(child: Center(child: VitaLoadingIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error))
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No usage recorded for this selection yet.\n'
                  'Taps and screen views are reported by the app release that includes usage tracking.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else ...[
            Expanded(child: _buildTable(isTap)),
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'People = distinct signed-in accounts. A dash means the activity happened before login, '
                'so it cannot be tied to a person.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTable(bool isTap) {
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final row = _rows[index];
          return VitaListCard(
            title: Text(isTap ? _nice(row.action) : row.screen),
            fields: [
              VitaListCard.kv('Flow', _flowLabel(row.flow)),
              if (isTap) VitaListCard.kv('Screen', row.screen),
              VitaListCard.kv(isTap ? 'Taps' : 'Views', '${row.count}'),
              VitaListCard.kv('People', _people(row)),
            ],
          );
        },
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('#')),
            const DataColumn(label: Text('Flow')),
            const DataColumn(label: Text('Screen')),
            if (isTap) const DataColumn(label: Text('Button')),
            DataColumn(label: Text(isTap ? 'Taps' : 'Views'), numeric: true),
            const DataColumn(label: Text('People'), numeric: true),
          ],
          rows: [
            for (var i = 0; i < _rows.length; i++)
              DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(Text(_flowLabel(_rows[i].flow))),
                DataCell(Text(_rows[i].screen)),
                if (isTap) DataCell(Text(_nice(_rows[i].action))),
                DataCell(Text('${_rows[i].count}')),
                DataCell(Text(_people(_rows[i]))),
              ]),
          ],
        ),
      ),
    );
  }
}
