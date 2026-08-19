import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/admin_organisations_repository.dart';

/// NurseNow hospital/rehab/clinic accounts — mirrors IndividualsListScreen
/// exactly (same two admin block levers, same table shape).
class OrganisationsListScreen extends ConsumerStatefulWidget {
  const OrganisationsListScreen({super.key});

  @override
  ConsumerState<OrganisationsListScreen> createState() => _OrganisationsListScreenState();
}

class _OrganisationsListScreenState extends ConsumerState<OrganisationsListScreen> {
  int _page = 1;
  List<AdminOrganisationListItem> _items = [];
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
      final result = await ref.read(adminOrganisationsRepositoryProvider).list(page: _page);
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

  Future<void> _showBlockDialog(AdminOrganisationListItem item, String level) async {
    final controller = TextEditingController();
    final label = level == 'full' ? 'Block completely' : 'Block from posting new requirements';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label — ${item.organisationName}'),
        content: TextField(
          controller: controller,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Reason (shown to the organisation)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminOrganisationsRepositoryProvider).block(item.userId, level, controller.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _unblock(AdminOrganisationListItem item, String level) async {
    try {
      await ref.read(adminOrganisationsRepositoryProvider).unblock(item.userId, level);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.rehabHospitals,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rehab / Hospitals', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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

  Widget _buildTable() {
    if (_items.isEmpty) {
      return const Center(child: Text('No organisation accounts yet.'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Organisation')),
            DataColumn(label: Text('Contact')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Location')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Registered')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _items.map((item) => DataRow(cells: [
                DataCell(Text(organisationDisplayId(item.orgNumber) ?? '-')),
                DataCell(Text(item.organisationName)),
                DataCell(Text(item.fullName)),
                DataCell(Text(item.phone)),
                DataCell(Text('${City.displayNames[item.city] ?? item.city}, ${item.area}')),
                DataCell(_StatusCell(item: item)),
                DataCell(Text(item.createdAt.split('T').first)),
                DataCell(_ActionsCell(
                  item: item,
                  onBlockJobPosting: () => _showBlockDialog(item, 'job_posting'),
                  onUnblockJobPosting: () => _unblock(item, 'job_posting'),
                  onBlockFull: () => _showBlockDialog(item, 'full'),
                  onUnblockFull: () => _unblock(item, 'full'),
                )),
              ])).toList(),
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
            onPressed: meta.page > 1 ? () { _page = meta.page - 1; _load(); } : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: meta.page < meta.totalPages ? () { _page = meta.page + 1; _load(); } : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  final AdminOrganisationListItem item;

  const _StatusCell({required this.item});

  @override
  Widget build(BuildContext context) {
    if (!item.isActive) {
      return Text('Blocked${item.blockReason != null ? ': ${item.blockReason}' : ''}',
          style: const TextStyle(color: AppColors.error));
    }
    if (item.isJobPostingBlocked) {
      return Text('Posting blocked${item.blockReason != null ? ': ${item.blockReason}' : ''}',
          style: const TextStyle(color: AppColors.error));
    }
    return const Text('Active', style: TextStyle(color: AppColors.success));
  }
}

class _ActionsCell extends StatelessWidget {
  final AdminOrganisationListItem item;
  final VoidCallback onBlockJobPosting;
  final VoidCallback onUnblockJobPosting;
  final VoidCallback onBlockFull;
  final VoidCallback onUnblockFull;

  const _ActionsCell({
    required this.item,
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
        if (item.isJobPostingBlocked)
          TextButton(onPressed: onUnblockJobPosting, child: const Text('Unblock Posting'))
        else
          TextButton(onPressed: onBlockJobPosting, child: const Text('Block Posting')),
        if (item.isActive)
          TextButton(onPressed: onBlockFull, child: const Text('Block'))
        else
          TextButton(onPressed: onUnblockFull, child: const Text('Unblock')),
      ],
    );
  }
}
