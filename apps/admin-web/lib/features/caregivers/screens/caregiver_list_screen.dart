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
import '../../../shared/widgets/inline_notes_panel.dart';
import '../../../shared/widgets/sort_bar.dart';
import '../data/admin_caregivers_repository.dart';
import '../data/admin_caregiver_models.dart';

class CaregiverListScreen extends ConsumerStatefulWidget {
  final String? initialStatus;

  const CaregiverListScreen({super.key, this.initialStatus});

  @override
  ConsumerState<CaregiverListScreen> createState() =>
      _CaregiverListScreenState();
}

class _CaregiverListScreenState extends ConsumerState<CaregiverListScreen> {
  final _searchController = TextEditingController();
  String? _status;
  String? _qualification;
  String? _gender;
  String? _language;
  String? _city;
  int _page = 1;
  String _sort = 'created_at';
  bool _sortAscending = false;

  List<AdminCaregiverListItem> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Sort key of each table column after the leading checkbox column;
  /// '' marks a column that can't be sorted.
  static const _columnSortKeys = ['created_at', 'caregiver_number', 'full_name', 'phone', 'gender', 'age', 'highest_qualification', 'verification_status'];

  int? get _sortColumnIndex {
    final i = _columnSortKeys.indexOf(_sort);
    return i < 0 ? null : i + 1;
  }

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(adminCaregiversRepositoryProvider).list(
            CaregiverListFilters(
              search: _searchController.text.trim().isEmpty
                  ? null
                  : _searchController.text.trim(),
              status: _status,
              qualification: _qualification,
              gender: _gender,
              languages: _language == null ? null : [_language!],
              city: _city,
              sort: _sort,
              order: _sortAscending ? 'asc' : 'desc',
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

  SelectedRecipient _toRecipient(AdminCaregiverListItem item) => SelectedRecipient(
        userId: item.userId,
        role: 'caregiver',
        displayName: item.fullName,
      );

  void _openDetail(AdminCaregiverListItem item) => Navigator.of(context)
      .pushNamed('/caregiver-detail', arguments: item.profileId);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.caregivers,
      bottomBar: const RecipientCartBar(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Caregivers',
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
                    SortOption('caregiver_number', 'ID'),
                    SortOption('full_name', 'Name'),
                    SortOption('phone', 'Phone'),
                    SortOption('gender', 'Gender'),
                    SortOption('age', 'Age'),
                    SortOption('highest_qualification', 'Qualification'),
                    SortOption('verification_status', 'Status'),
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
              labelText: 'Search name, phone, or ID (NUR-...)',
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
            initialValue: _status,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.flag_outlined),
                labelText: 'Status',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All statuses')),
              ...VerificationStatus.all.map(
                  (s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
            ],
            onChanged: (value) => setState(() => _status = value),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _qualification,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.school),
                labelText: 'Qualification',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All qualifications')),
              ...Qualification.all.map((q) => DropdownMenuItem<String?>(
                  value: q, child: Text(Qualification.displayNames[q] ?? q))),
            ],
            onChanged: (value) => setState(() => _qualification = value),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _gender,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.wc),
                labelText: 'Gender',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All genders')),
              ...Gender.all.map((g) => DropdownMenuItem<String?>(
                  value: g, child: Text(g[0].toUpperCase() + g.substring(1)))),
            ],
            onChanged: (value) => setState(() => _gender = value),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _language,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.language),
                labelText: 'Language',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All languages')),
              ...Language.all.map((l) => DropdownMenuItem<String?>(
                  value: l, child: Text(Language.displayNames[l] ?? l))),
            ],
            onChanged: (value) => setState(() => _language = value),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _city,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_city),
                labelText: 'Preferred City',
                border: OutlineInputBorder(),
                isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('All cities')),
              ...City.all.map((c) => DropdownMenuItem<String?>(
                  value: c, child: Text(City.displayNames[c] ?? c))),
            ],
            onChanged: (value) => setState(() => _city = value),
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

  Widget _buildTable() {
    if (_items.isEmpty) {
      return const Center(child: Text('No caregivers match these filters.'));
    }
    final cart = ref.watch(recipientSelectionCartProvider);
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            // No card-level onTap — see IndividualsListScreen's identical
            // comment for why (Checkbox + whole-card InkWell both fire on
            // the same tap). Only the caregiver's name opens the detail
            // screen.
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
            trailing: VitaStatusBadge(status: item.verificationStatus),
            fields: [
              VitaListCard.kv(
                  'ID', caregiverDisplayId(item.caregiverNumber) ?? '-'),
              PhoneWithContact(label: 'Phone', phone: item.phone),
              VitaListCard.kv('Gender', item.gender),
              VitaListCard.kv('Age', '${item.age}'),
              VitaListCard.kv(
                'Qualification',
                Qualification.displayNames[item.highestQualification] ??
                    item.highestQualification ??
                    '-',
              ),
              VitaListCard.kv('Registered', item.createdAt.split('T').first),
              InlineNotesPanel(
                key: ValueKey('notes-${item.profileId}'),
                subject: 'this caregiver',
                notes: item.notes,
                onSave: (notes) => _saveNotes(item, notes),
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
            DataColumn(label: const Text('ID'), onSort: (_, __) => _sortBy('caregiver_number')),
            DataColumn(label: const Text('Name'), onSort: (_, __) => _sortBy('full_name')),
            DataColumn(label: const Text('Phone'), onSort: (_, __) => _sortBy('phone')),
            DataColumn(label: const Text('Gender'), onSort: (_, __) => _sortBy('gender')),
            DataColumn(label: const Text('Age'), onSort: (_, __) => _sortBy('age')),
            DataColumn(label: const Text('Qualification'), onSort: (_, __) => _sortBy('highest_qualification')),
            DataColumn(label: const Text('Status'), onSort: (_, __) => _sortBy('verification_status')),
            DataColumn(label: const Text('Registered'), onSort: (_, __) => _sortBy('created_at')),
            const DataColumn(label: Text('Notes')),
          ],
          rows: _items
              .map(
                (item) => DataRow(
                  // No row-level onSelectChanged — see
                  // IndividualsListScreen's identical comment. Navigation
                  // instead uses DataCell's own per-cell onTap, below.
                  cells: [
                    DataCell(
                      Checkbox(
                        value: cart.containsKey(item.userId),
                        onChanged: (_) => ref
                            .read(recipientSelectionCartProvider.notifier)
                            .toggle(_toRecipient(item)),
                      ),
                    ),
                    DataCell(Text(caregiverDisplayId(item.caregiverNumber) ?? '-'),
                        onTap: () => _openDetail(item)),
                    DataCell(Text(item.fullName), onTap: () => _openDetail(item)),
                    DataCell(PhoneWithContact(phone: item.phone)),
                    DataCell(Text(item.gender), onTap: () => _openDetail(item)),
                    DataCell(Text('${item.age}'), onTap: () => _openDetail(item)),
                    DataCell(
                        Text(Qualification.displayNames[item.highestQualification] ??
                            item.highestQualification ??
                            '-'),
                        onTap: () => _openDetail(item)),
                    DataCell(VitaStatusBadge(status: item.verificationStatus),
                        onTap: () => _openDetail(item)),
                    DataCell(Text(item.createdAt.split('T').first),
                        onTap: () => _openDetail(item)),
                    DataCell(_notesCell(item)),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _saveNotes(AdminCaregiverListItem item, String notes) async {
    await ref
        .read(adminCaregiversRepositoryProvider)
        .upsertInternalNotes(item.profileId, notes);
    if (mounted) await _load();
  }

  Widget _notesCell(AdminCaregiverListItem item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: SizedBox(
          width: 300,
          child: InlineNotesPanel(
            key: ValueKey('notes-${item.profileId}'),
            subject: 'this caregiver',
            notes: item.notes,
            compact: true,
            onSave: (notes) => _saveNotes(item, notes),
          ),
        ),
      );

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
