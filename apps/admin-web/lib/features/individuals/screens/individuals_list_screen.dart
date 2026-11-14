import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../../../shared/widgets/recipient_cart_bar.dart';
import '../../../shared/state/recipient_selection_cart.dart';
import '../../jobs/screens/admin_jobs_screen.dart';
import '../data/admin_individuals_repository.dart';
import '../../../shared/widgets/action_help.dart';
import '../../../shared/widgets/inline_notes_panel.dart';
import '../../../shared/widgets/sort_bar.dart';

/// NurseNow patient/family accounts. No verification pipeline like
/// caregivers — just the two admin block levers (job-posting-only vs full
/// login lockout), each with an admin-entered reason the individual sees.
class IndividualsListScreen extends ConsumerStatefulWidget {
  const IndividualsListScreen({super.key});

  @override
  ConsumerState<IndividualsListScreen> createState() =>
      _IndividualsListScreenState();
}

class _IndividualsListScreenState extends ConsumerState<IndividualsListScreen> {
  int _page = 1;
  String _sort = 'created_at';
  bool _sortAscending = false;
  List<AdminIndividualListItem> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _errorMessage;

  final _searchController = TextEditingController();
  String? _blockStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Sort key of each table column after the leading checkbox column;
  /// '' marks a column that can't be sorted.
  static const _columnSortKeys = ['created_at', 'patient_number', 'full_name', 'phone', '', '', ''];

  int? get _sortColumnIndex {
    final i = _columnSortKeys.indexOf(_sort);
    return i < 0 ? null : i + 1;
  }

  /// The first [length] characters of [text], with the full text on hover.
  Widget _shortWithHover(String text, int length) {
    if (text.length <= length) return Text(text);
    return Tooltip(message: text, child: Text('${text.substring(0, length)}…'));
  }

  Future<void> _saveNotes(dynamic item, String notes) async {
    await ref.read(adminIndividualsRepositoryProvider).upsertNotes(item.userId, notes);
    if (mounted) await _load(silent: true);
  }

  Widget _notesCell(dynamic item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: SizedBox(
          width: 300,
          child: InlineNotesPanel(
            key: ValueKey('notes-${item.userId}'),
            subject: 'this patient',
            notes: item.notes,
            compact: true,
            onSave: (notes) => _saveNotes(item, notes),
          ),
        ),
      );

  void _setSort(String key, bool ascending) {
    setState(() {
      _sort = key;
      _sortAscending = ascending;
      _page = 1;
    });
    _load();
  }

  void _sortBy(String key) {
    final (nextKey, ascending) = nextSort(
        currentKey: _sort, currentAscending: _sortAscending, tappedKey: key);
    _setSort(nextKey, ascending);
  }

  /// [silent] refreshes in place after an action (save notes, block, ...): no
  /// loading spinner, so the list keeps its scroll position.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(adminIndividualsRepositoryProvider).list(
            page: _page,
            filters: IndividualListFilters(
              search: _searchController.text.trim().isEmpty
                  ? null
                  : _searchController.text.trim(),
              blockStatus: _blockStatus,
              sort: _sort,
              order: _sortAscending ? 'asc' : 'desc',
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

  bool get _hasActiveFilters =>
      _blockStatus != null || _searchController.text.trim().isNotEmpty;

  Widget _buildFilterPanel() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search name, phone, or ID (PAT-...)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _applyFilters(),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _blockStatus,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.flag_outlined),
                labelText: 'Status',
                border: OutlineInputBorder(),
                isDense: true),
            items: const [
              DropdownMenuItem<String?>(
                  value: null, child: Text('All statuses')),
              DropdownMenuItem<String?>(value: 'active', child: Text('Active')),
              DropdownMenuItem<String?>(
                  value: 'job_posting_blocked', child: Text('Posting Blocked')),
              DropdownMenuItem<String?>(
                  value: 'blocked', child: Text('Blocked')),
            ],
            onChanged: (value) => setState(() => _blockStatus = value),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _applyFilters,
          icon: const Icon(Icons.filter_alt, size: 18),
          label: const Text('Apply Filters'),
        ),
      ],
    );
  }

  Future<void> _showBlockDialog(
      AdminIndividualListItem item, String level) async {
    final controller = TextEditingController();
    final label = level == 'full'
        ? 'Block completely'
        : 'Block from posting new requirements';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label — ${item.fullName}'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Reason (shown to the individual)'),
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
      await ref
          .read(adminIndividualsRepositoryProvider)
          .block(item.userId, level, controller.text.trim());
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _unblock(AdminIndividualListItem item, String level) async {
    try {
      await ref
          .read(adminIndividualsRepositoryProvider)
          .unblock(item.userId, level);
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  /// Redirects into the merged Jobs tab, pre-filtered to just this
  /// individual's own postings — every other Jobs filter (search/city/
  /// status/etc.) stays available to narrow further from there.
  SelectedRecipient _toRecipient(AdminIndividualListItem item) => SelectedRecipient(
        userId: item.userId,
        role: 'individual',
        displayName: item.fullName,
      );

  void _openDetail(AdminIndividualListItem item) => Navigator.of(context)
      .pushNamed('/individual-detail', arguments: item.userId);

  void _viewJobs(AdminIndividualListItem item) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/jobs',
      (route) => false,
      arguments: JobsScreenInitialFilter(
        postedByUserId: item.userId,
        postedByLabel: item.fullName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.patientsFamily,
      bottomBar: const RecipientCartBar(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Patients / Family',
                  style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.md),
              _buildFilterPanel(),
              const SizedBox(height: AppSpacing.xs),
              // Wide layouts sort by clicking the table's column headers; the
              // narrow card layout has no headers, so it gets this control.
              if (context.isMobile) ...[
                SortBar(
                  options: const [
                    SortOption('created_at', 'Registered'),
                    SortOption('patient_number', 'ID'),
                    SortOption('full_name', 'Name'),
                    SortOption('phone', 'Phone'),
                  ],
                  sortKey: _sort,
                  ascending: _sortAscending,
                  onChanged: _setSort,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!,
                    style: const TextStyle(color: AppColors.error))
              else
                Expanded(child: _buildTable()),
              if (_meta != null) _buildPager(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    if (_items.isEmpty) {
      return Center(
        child: Text(_hasActiveFilters
            ? 'No individual accounts match these filters.'
            : 'No individual accounts yet.'),
      );
    }
    final cart = ref.watch(recipientSelectionCartProvider);
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            // No card-level onTap here — with the Checkbox embedded in the
            // title, a tap-anywhere InkWell behind it fires on top of the
            // Checkbox's own tap too (both land in the same gesture arena),
            // toggling the checkbox AND navigating away in one tap. Only
            // the name text itself opens the detail screen; the checkbox
            // area is deliberately excluded from any navigation gesture.
            title: Row(
              children: [
                Checkbox(
                  value: cart.containsKey(item.userId),
                  onChanged: (_) => ref
                      .read(recipientSelectionCartProvider.notifier)
                      .toggle(_toRecipient(item)),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openDetail(item),
                    child: Text(item.fullName, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            trailing: _StatusCell(item: item),
            fields: [
              VitaListCard.kv(
                  'ID', patientDisplayId(item.patientNumber) ?? '-'),
              PhoneWithContact(label: 'Phone', phone: item.phone),
              VitaListCard.kv('Registered', item.createdAt.split('T').first),
              InlineNotesPanel(
                key: ValueKey('notes-${item.userId}'),
                subject: 'this patient',
                notes: item.notes,
                onSave: (notes) => _saveNotes(item, notes),
              ),
            ],
            actions: [
              _ActionsCell(
                item: item,
                onViewJobs: () => _viewJobs(item),
                onBlockJobPosting: () => _showBlockDialog(item, 'job_posting'),
                onUnblockJobPosting: () => _unblock(item, 'job_posting'),
                onBlockFull: () => _showBlockDialog(item, 'full'),
                onUnblockFull: () => _unblock(item, 'full'),
              ),
            ],
          );
        },
      );
    }
    final allSelected = _items.every((item) => cart.containsKey(item.userId));
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          // Rows grow with the notes box.
          columnSpacing: 12,
          horizontalMargin: 8,
          dataRowMinHeight: 72,
          dataRowMaxHeight: double.infinity,
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          columns: [
            DataColumn(
              label: Checkbox(
                value: allSelected,
                onChanged: (value) {
                  final notifier = ref.read(recipientSelectionCartProvider.notifier);
                  if (value == true) {
                    notifier.addAll(_items.map(_toRecipient));
                  } else {
                    notifier.removeAll(_items.map((item) => item.userId));
                  }
                },
              ),
            ),
            DataColumn(label: const Text('Registered'), onSort: (_, __) => _sortBy('created_at')),
            DataColumn(label: const Text('ID'), onSort: (_, __) => _sortBy('patient_number')),
            DataColumn(label: const Text('Name'), onSort: (_, __) => _sortBy('full_name')),
            DataColumn(label: const Text('Phone'), onSort: (_, __) => _sortBy('phone')),
            const DataColumn(label: Text('Status')),
            const DataColumn(label: Text('Notes')),
            const DataColumn(label: Text('Actions')),
          ],
          rows: _items
              .map((item) => DataRow(
                      // No row-level onSelectChanged — DataTable wraps
                      // every cell in a tap-to-select GestureDetector when
                      // it's set, which fires alongside (not instead of)
                      // the Checkbox cell's own tap. Navigation instead
                      // uses DataCell's own per-cell onTap, below, which
                      // only the non-checkbox cells get.
                      cells: [
                        DataCell(
                          Checkbox(
                            value: cart.containsKey(item.userId),
                            onChanged: (_) => ref
                                .read(recipientSelectionCartProvider.notifier)
                                .toggle(_toRecipient(item)),
                          ),
                        ),
                        DataCell(Text(item.createdAt.split('T').first),
                            onTap: () => _openDetail(item)),
                        DataCell(
                            Text(patientDisplayId(item.patientNumber) ?? '-'),
                            onTap: () => _openDetail(item)),
                        DataCell(_shortWithHover(item.fullName, 10),
                            onTap: () => _openDetail(item)),
                        DataCell(PhoneWithContact(phone: item.phone)),
                        DataCell(_StatusCell(item: item), onTap: () => _openDetail(item)),
                        DataCell(_notesCell(item)),
                        DataCell(_ActionsCell(
                          item: item,
                          onViewJobs: () => _viewJobs(item),
                          onBlockJobPosting: () =>
                              _showBlockDialog(item, 'job_posting'),
                          onUnblockJobPosting: () =>
                              _unblock(item, 'job_posting'),
                          onBlockFull: () => _showBlockDialog(item, 'full'),
                          onUnblockFull: () => _unblock(item, 'full'),
                        )),
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
      // Wrap, not Row — "Page X of Y (Z total)" plus 2 icon buttons
      // overflows a Row on a narrow phone width; Wrap drops the buttons to
      // a second line instead.
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

class _StatusCell extends StatelessWidget {
  final AdminIndividualListItem item;

  const _StatusCell({required this.item});

  @override
  Widget build(BuildContext context) {
    if (!item.isActive) {
      return Text(
          'Blocked${item.blockReason != null ? ': ${item.blockReason}' : ''}',
          style: const TextStyle(color: AppColors.error));
    }
    if (item.isJobPostingBlocked) {
      return Text(
          'Posting blocked${item.blockReason != null ? ': ${item.blockReason}' : ''}',
          style: const TextStyle(color: AppColors.error));
    }
    return const Text('Active', style: TextStyle(color: AppColors.success));
  }
}

class _ActionsCell extends StatelessWidget {
  final AdminIndividualListItem item;
  final VoidCallback onViewJobs;
  final VoidCallback onBlockJobPosting;
  final VoidCallback onUnblockJobPosting;
  final VoidCallback onBlockFull;
  final VoidCallback onUnblockFull;

  const _ActionsCell({
    required this.item,
    required this.onViewJobs,
    required this.onBlockJobPosting,
    required this.onUnblockJobPosting,
    required this.onBlockFull,
    required this.onUnblockFull,
  });

  // A DataTable row has one fixed height shared by every row in the
  // table — a Wrap of 3 text buttons whose labels vary in width by state
  // ("Unblock Posting"/"Unblock" vs "Block Posting"/"Block Profile") could
  // wrap to a second line on some rows but not others, and that second
  // line had nowhere to go but overlap into the row below (confirmed live
  // — widening the row height wasn't enough to reliably fix it). Moving
  // the two block toggles into an overflow menu means this cell is always
  // exactly one button + one fixed-size icon button, on one line, at any
  // width — the popup's own item labels don't affect row layout at all.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionHelp(
          message: AdminHelp.viewJobsPosted,
          child: TextButton.icon(
            onPressed: onViewJobs,
            icon: const Icon(Icons.work_outline, size: 16),
            label: const Text('View Jobs'),
          ),
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'More actions',
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            if (item.isJobPostingBlocked)
              PopupMenuItem(
                value: onUnblockJobPosting,
                child: ActionHelp(
                  message: AdminHelp.unblockPosting,
                  child: const _MenuLabel(
                    icon: Icons.lock_open,
                    color: AppColors.success,
                    label: 'Unblock Posting',
                  ),
                ),
              )
            else
              PopupMenuItem(
                value: onBlockJobPosting,
                child: ActionHelp(
                  message: AdminHelp.blockPosting,
                  child: const _MenuLabel(
                    icon: Icons.block,
                    color: AppColors.error,
                    label: 'Block Posting',
                  ),
                ),
              ),
            if (item.isActive)
              PopupMenuItem(
                value: onBlockFull,
                child: ActionHelp(
                  message: AdminHelp.blockProfile,
                  child: const _MenuLabel(
                    icon: Icons.person_off,
                    color: AppColors.error,
                    label: 'Block Profile',
                  ),
                ),
              )
            else
              PopupMenuItem(
                value: onUnblockFull,
                child: ActionHelp(
                  message: AdminHelp.unblockProfile,
                  child: const _MenuLabel(
                    icon: Icons.lock_open,
                    color: AppColors.success,
                    label: 'Unblock',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// An icon + label pair for a PopupMenuItem — color-coded so a destructive
/// action (block) and a restorative one (unblock) read apart at a glance,
/// not just by their words.
class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _MenuLabel({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );
  }
}
