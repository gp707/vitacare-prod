import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_push_notifications_repository.dart';

/// History of every push notification an admin has composed — pending
/// (scheduled, not yet due), sent, failed, or cancelled. The only action
/// here is Cancel, and only while still pending — composing a new one
/// happens from RecipientCartBar on the Caregivers/Patients-Family/Rehab-
/// Hospitals list screens, not from this screen.
class PushNotificationsScreen extends ConsumerStatefulWidget {
  const PushNotificationsScreen({super.key});

  @override
  ConsumerState<PushNotificationsScreen> createState() => _PushNotificationsScreenState();
}

class _PushNotificationsScreenState extends ConsumerState<PushNotificationsScreen> {
  int _page = 1;
  List<AdminPushNotificationItem> _items = [];
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
      final result = await ref.read(adminPushNotificationsRepositoryProvider).list(page: _page);
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

  Future<void> _cancel(AdminPushNotificationItem item) async {
    try {
      await ref.read(adminPushNotificationsRepositoryProvider).cancel(item.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.pushNotifications,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Push Notifications',
                  style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Compose a new notification by selecting recipients on the Caregivers, '
                'Patients/Family, or Rehab/Hospitals screens.',
                style: TextStyle(color: AppColors.textSecondary),
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
      return const Center(child: Text('No push notifications sent yet.'));
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text(item.title),
            trailing: _StatusChip(status: item.status),
            fields: [
              VitaListCard.kv('Message', item.body),
              VitaListCard.kv('Recipients', '${item.recipientCount}'),
              VitaListCard.kv('Scheduled', item.scheduledAt.split('T').first),
              VitaListCard.kv('By', item.createdByName),
            ],
            actions: [
              if (item.status == 'pending')
                TextButton.icon(
                  onPressed: () => _cancel(item),
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                  label: const Text('Cancel', style: TextStyle(color: AppColors.error)),
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
            DataColumn(label: Text('Title')),
            DataColumn(label: Text('Message')),
            DataColumn(label: Text('Recipients')),
            DataColumn(label: Text('Scheduled')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Sent By')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _items
              .map((item) => DataRow(cells: [
                    DataCell(Text(item.title)),
                    DataCell(SizedBox(width: 280, child: Text(item.body, overflow: TextOverflow.ellipsis))),
                    DataCell(Text('${item.recipientCount}')),
                    DataCell(Text(_formatDateTime(item.scheduledAt))),
                    DataCell(_StatusChip(status: item.status)),
                    DataCell(Text(item.createdByName)),
                    DataCell(
                      item.status == 'pending'
                          ? TextButton(
                              onPressed: () => _cancel(item),
                              child: const Text('Cancel', style: TextStyle(color: AppColors.error)),
                            )
                          : const SizedBox.shrink(),
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

  String _formatDateTime(String isoUtc) {
    final d = DateTime.parse(isoUtc).toLocal();
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'sent' => AppColors.success,
      'pending' => Colors.orange,
      'failed' => AppColors.error,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600),
      ),
    );
  }
}
