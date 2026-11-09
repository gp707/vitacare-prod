import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_rejections_repository.dart';

const _closeReasonLabels = {
  'duty_complete': 'Duty complete',
  'no_reason': 'No reason given',
  'did_not_like_work': 'Did not like the work',
  'temporarily_not_available': 'Temporarily not available',
  'family_problems': 'Family problems',
  'need_to_go_hometown': 'Need to go to hometown',
};

String _eventLabel(String event) {
  switch (event) {
    case 'caregiver_declined':
      return 'Caregiver declined';
    case 'caregiver_closed':
      return 'Caregiver closed job';
    default:
      return 'Rejected caregiver';
  }
}

Color _eventColor(String event) => event == 'poster_rejected' ? AppColors.error : Colors.orange;

/// Plain-words reason: the poster's own text, the caregiver's close reason,
/// or an honest "not collected" for a caregiver's outright decline.
String _reasonText(AdminRejectionItem item) {
  final reason = item.reason?.trim();
  if (item.event == 'caregiver_declined') return 'No reason is asked when a caregiver declines';
  if (reason == null || reason.isEmpty) return 'No reason given';
  if (item.event == 'caregiver_closed') return _closeReasonLabels[reason] ?? reason;
  return reason;
}

/// Who said no to whom, and why: caregivers declining or closing a job, and
/// patients/organisations (or an admin) rejecting a caregiver.
class RejectionsScreen extends ConsumerStatefulWidget {
  const RejectionsScreen({super.key});

  @override
  ConsumerState<RejectionsScreen> createState() => _RejectionsScreenState();
}

class _RejectionsScreenState extends ConsumerState<RejectionsScreen> {
  int _page = 1;
  String? _direction;
  String _search = '';
  List<AdminRejectionItem> _items = [];
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
      final result = await ref
          .read(adminRejectionsRepositoryProvider)
          .list(page: _page, direction: _direction, search: _search);
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

  void _applyFilter(String? direction) {
    setState(() => _direction = direction);
    _page = 1;
    _load();
  }

  void _openCaregiver(AdminRejectionItem item) =>
      Navigator.of(context).pushNamed('/caregiver-detail', arguments: item.caregiverProfileId);

  String _by(AdminRejectionItem item) {
    if (item.event != 'poster_rejected') return item.caregiverName;
    final name = item.decidedByName ?? item.posterName ?? '-';
    final isAdmin = item.decidedByRole == 'admin' || item.decidedByRole == 'super_admin';
    return isAdmin ? '$name (admin)' : name;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.rejections,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rejections',
                  style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Caregivers who declined or closed a job, and patients, organisations or admins who '
                'rejected a caregiver — with the reason given.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: _direction,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.swap_horiz),
                        labelText: 'Who rejected',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('Everyone')),
                        DropdownMenuItem<String?>(value: 'poster', child: Text('Patient / organisation / admin')),
                        DropdownMenuItem<String?>(value: 'caregiver', child: Text('Caregiver')),
                      ],
                      onChanged: _applyFilter,
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search name, phone, NUR-id, reason',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        _search = value.trim();
                        _page = 1;
                        _load();
                      },
                    ),
                  ),
                ],
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
    if (_items.isEmpty) return const Center(child: Text('No rejections match this filter.'));
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text(item.caregiverName),
            trailing: _EventChip(event: item.event),
            onTap: () => _openCaregiver(item),
            fields: [
              VitaListCard.kv('Caregiver', '${item.caregiverDisplayLabel ?? '-'} · ${item.caregiverPhone}'),
              VitaListCard.kv('Job', item.jobLabel),
              VitaListCard.kv('Posted by', '${item.posterName ?? '-'} ${item.posterDisplayLabel ?? ''}'.trim()),
              VitaListCard.kv('Rejected by', _by(item)),
              VitaListCard.kv('Reason', _reasonText(item)),
              VitaListCard.kv('When', item.occurredAt.split('T').first),
            ],
          );
        },
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 52,
          dataRowMaxHeight: 88,
          columns: const [
            DataColumn(label: Text('When')),
            DataColumn(label: Text('What happened')),
            DataColumn(label: Text('Caregiver')),
            DataColumn(label: Text('Job')),
            DataColumn(label: Text('Posted by')),
            DataColumn(label: Text('Rejected by')),
            DataColumn(label: Text('Reason')),
          ],
          rows: _items
              .map((item) => DataRow(cells: [
                    DataCell(Text(item.occurredAt.split('T').first)),
                    DataCell(_EventChip(event: item.event)),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item.caregiverDisplayLabel ?? '-'}  ${item.caregiverName}'),
                          Text(item.caregiverPhone,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: AppTypography.small)),
                        ],
                      ),
                      onTap: () => _openCaregiver(item),
                    ),
                    DataCell(Text(item.jobLabel)),
                    DataCell(Text('${item.posterName ?? '-'}\n${item.posterDisplayLabel ?? ''}'.trim())),
                    DataCell(Text(_by(item))),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(_reasonText(item), softWrap: true, maxLines: 4, overflow: TextOverflow.ellipsis),
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

class _EventChip extends StatelessWidget {
  final String event;

  const _EventChip({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(event);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _eventLabel(event),
        style: TextStyle(color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600),
      ),
    );
  }
}
