import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_tickets_repository.dart';

/// Support tickets — currently only ever created by the "Forgot PIN" link
/// on any login screen (caregiver, individual, organisation): there's no
/// OTP/email PIN reset, so that link creates a ticket here instead, and
/// admin verifies the requester's identity out of band before resetting
/// their PIN via the existing Reset PIN action on that account's own
/// detail screen (see CaregiverDetailScreen/IndividualDetailScreen/
/// OrganisationDetailScreen).
class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  int _page = 1;
  String? _status = 'open';
  List<AdminTicketItem> _items = [];
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
      final result = await ref.read(adminTicketsRepositoryProvider).list(page: _page, status: _status);
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

  void _applyFilter(String? status) {
    setState(() => _status = status);
    _page = 1;
    _load();
  }

  Future<void> _resolve(AdminTicketItem item) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Resolve ticket — ${item.userFullName}'),
        content: TextField(
          controller: notesController,
          maxLength: 1000,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Resolution notes (optional)'),
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
            label: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminTicketsRepositoryProvider).resolve(item.id, notes: notesController.text.trim());
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  void _openAccount(AdminTicketItem item) {
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

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.tickets,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tickets',
                  style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Requests from patients, caregivers, or organisations who tapped "Forgot PIN?" — '
                'verify identity out of band, then reset their PIN from their own detail screen.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.flag_outlined),
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                    DropdownMenuItem<String?>(value: 'open', child: Text('Open')),
                    DropdownMenuItem<String?>(value: 'resolved', child: Text('Resolved')),
                  ],
                  onChanged: _applyFilter,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else
                Expanded(child: _buildList()),
              if (_meta != null) _buildPager(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return const Center(child: Text('No tickets match this filter.'));
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text(item.userFullName),
            trailing: _StatusChip(status: item.status),
            onTap: () => _openAccount(item),
            fields: [
              VitaListCard.kv('ID', item.displayId ?? '-'),
              VitaListCard.kv('Role', _roleLabel(item.userRole)),
              VitaListCard.kv('Phone', item.phone),
              VitaListCard.kv('Type', 'Forgot PIN'),
              VitaListCard.kv('Opened', item.createdAt.split('T').first),
              if (item.resolvedByName != null) VitaListCard.kv('Resolved By', item.resolvedByName!),
            ],
            actions: [
              if (item.status == 'open')
                ElevatedButton.icon(
                  onPressed: () => _resolve(item),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Resolve'),
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
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Opened')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _items
              .map((item) => DataRow(cells: [
                    DataCell(Text(item.displayId ?? '-'), onTap: () => _openAccount(item)),
                    DataCell(Text(item.userFullName), onTap: () => _openAccount(item)),
                    DataCell(Text(_roleLabel(item.userRole)), onTap: () => _openAccount(item)),
                    DataCell(Text(item.phone), onTap: () => _openAccount(item)),
                    DataCell(const Text('Forgot PIN')),
                    DataCell(_StatusChip(status: item.status)),
                    DataCell(Text(item.createdAt.split('T').first)),
                    DataCell(
                      item.status == 'open'
                          ? ElevatedButton(
                              onPressed: () => _resolve(item),
                              child: const Text('Resolve'),
                            )
                          : Text(item.resolvedByName != null ? 'By ${item.resolvedByName}' : '-'),
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
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'resolved' ? AppColors.success : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status == 'resolved' ? 'Resolved' : 'Open',
        style: TextStyle(color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600),
      ),
    );
  }
}
