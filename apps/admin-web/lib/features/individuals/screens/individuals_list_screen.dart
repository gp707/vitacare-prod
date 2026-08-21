import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../../jobs/screens/admin_jobs_screen.dart';
import '../data/admin_individuals_repository.dart';

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
        ElevatedButton(
            onPressed: _applyFilters, child: const Text('Apply Filters')),
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
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(adminIndividualsRepositoryProvider)
          .block(item.userId, level, controller.text.trim());
      await _load();
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
      await _load();
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
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Patients / Family',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.md),
              _buildFilterPanel(),
              const SizedBox(height: AppSpacing.md),
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
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text(item.fullName),
            trailing: _StatusCell(item: item),
            onTap: () => Navigator.of(context)
                .pushNamed('/individual-detail', arguments: item.userId),
            fields: [
              VitaListCard.kv(
                  'ID', patientDisplayId(item.patientNumber) ?? '-'),
              VitaListCard.kv('Phone', item.phone),
              VitaListCard.kv('Registered', item.createdAt.split('T').first),
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
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Registered')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _items
              .map((item) => DataRow(
                      onSelectChanged: (_) => Navigator.of(context).pushNamed(
                          '/individual-detail',
                          arguments: item.userId),
                      cells: [
                        DataCell(
                            Text(patientDisplayId(item.patientNumber) ?? '-')),
                        DataCell(Text(item.fullName)),
                        DataCell(Text(item.phone)),
                        DataCell(_StatusCell(item: item)),
                        DataCell(Text(item.createdAt.split('T').first)),
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        TextButton(onPressed: onViewJobs, child: const Text('View Jobs')),
        if (item.isJobPostingBlocked)
          TextButton(
              onPressed: onUnblockJobPosting,
              child: const Text('Unblock Posting'))
        else
          TextButton(
              onPressed: onBlockJobPosting, child: const Text('Block Posting')),
        if (item.isActive)
          TextButton(onPressed: onBlockFull, child: const Text('Block'))
        else
          TextButton(onPressed: onUnblockFull, child: const Text('Unblock')),
      ],
    );
  }
}
