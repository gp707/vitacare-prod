import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/open_job.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_accepted_repository.dart';

String _statusLabel(String status) {
  switch (status) {
    case 'accepted':
      return 'Working';
    case 'completed':
      return 'Closed duty';
    case 'rejected':
      return 'Later rejected';
    case 'applied':
      return 'Re-applied';
    default:
      return status;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'accepted':
      return AppColors.success;
    case 'completed':
      return AppColors.textSecondary;
    case 'rejected':
      return AppColors.error;
    default:
      return Colors.orange;
  }
}

/// Every caregiver who was accepted onto a job or organisation requirement, with what has
/// happened since — the counterpart of the Rejections screen. The status is the
/// application's current one, so a caregiver accepted and later let go reads "Later
/// rejected". Who accepted them is only known while they are still working or closed duty
/// (a later rejection overwrites it).
class AcceptedScreen extends ConsumerStatefulWidget {
  const AcceptedScreen({super.key});

  @override
  ConsumerState<AcceptedScreen> createState() => _AcceptedScreenState();
}

class _AcceptedScreenState extends ConsumerState<AcceptedScreen> {
  int _page = 1;
  String? _status;
  String _search = '';
  List<AdminAcceptedItem> _items = [];
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
      final result = await ref.read(adminAcceptedRepositoryProvider).list(page: _page, status: _status, search: _search);
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

  void _openCaregiver(AdminAcceptedItem item) =>
      Navigator.of(context).pushNamed('/caregiver-detail', arguments: item.caregiverProfileId);

  /// Opens the job (or organisation requirement) this row is about, in place.
  Future<void> _openJob(AdminAcceptedItem item) =>
      openJobOrRequirement(context, ref, jobId: item.jobId, isRequirement: item.isRequirement);

  /// Opens the profile of whoever accepted: a patient/family or an organisation (an admin has none).
  void _openAcceptedBy(AdminAcceptedItem item) {
    if (!item.acceptedByHasProfile) return;
    Navigator.of(context).pushNamed(
      item.acceptedByRole == 'organisation' ? '/organisation-detail' : '/individual-detail',
      arguments: item.acceptedById,
    );
  }

  /// A hover card (multi-line) around [child]; shows quickly and stays long enough to read.
  Widget _hover(String message, Widget child) => Tooltip(
        message: message,
        waitDuration: const Duration(milliseconds: 250),
        showDuration: const Duration(seconds: 10),
        preferBelow: false,
        textAlign: TextAlign.left,
        child: child,
      );

  /// Text that looks and behaves like a link.
  Widget _linkText(String text, {Key? key}) => Text(
        text,
        key: key,
        style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline),
      );

  String _by(AdminAcceptedItem item) {
    final name = item.acceptedByName;
    if (name == null) return '-';
    final isAdmin = item.acceptedByRole == 'admin' || item.acceptedByRole == 'super_admin';
    return isAdmin ? '$name (admin)' : name;
  }

  /// "₹30,000 per month, cycle from 2026-11-01", or a dash when nothing was agreed.
  String _agreed(AdminAcceptedItem item) {
    final salary = item.agreedSalaryText;
    if (salary == null) return '-';
    final start = item.agreedStartDate;
    return start == null ? salary : '$salary\nStarts ${formatLongDate(start)}';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.accepted,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Accepted', style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Every caregiver accepted onto a job or requirement by a patient, organisation or admin — '
                'and what has happened since.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('accepted-filter-status'),
                      isExpanded: true,
                      initialValue: _status,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.flag_outlined),
                        labelText: 'Status now',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('All')),
                        DropdownMenuItem<String?>(value: 'accepted', child: Text('Working')),
                        DropdownMenuItem<String?>(value: 'completed', child: Text('Closed duty')),
                        DropdownMenuItem<String?>(value: 'rejected', child: Text('Later rejected')),
                        DropdownMenuItem<String?>(value: 'applied', child: Text('Re-applied')),
                      ],
                      onChanged: _applyFilter,
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      key: const Key('accepted-search'),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search name, phone, NUR-/PAT-/ORG- id, job id',
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
    if (_items.isEmpty) {
      return const Center(child: Text('Nobody has been accepted yet for this filter.', key: Key('accepted-empty')));
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text(item.caregiverName),
            trailing: _StatusChip(status: item.status),
            onTap: () => _openCaregiver(item),
            fields: [
              VitaListCard.kv('Caregiver', item.caregiverDisplayLabel ?? '-'),
              PhoneWithContact(label: 'Phone', phone: item.caregiverPhone),
              VitaListCard.kv('Job', item.jobLabel),
              VitaListCard.kv('Posted by', '${item.posterName ?? '-'} ${item.posterDisplayLabel ?? ''}'.trim()),
              VitaListCard.kv('Accepted by', _by(item)),
              VitaListCard.kv('Agreed', _agreed(item).replaceAll('\n', ', ')),
              VitaListCard.kv('Accepted', item.acceptedAt.split('T').first),
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
            DataColumn(label: Text('Accepted')),
            DataColumn(label: Text('Status now')),
            DataColumn(label: Text('Caregiver')),
            DataColumn(label: Text('Job')),
            DataColumn(label: Text('Posted by')),
            DataColumn(label: Text('Accepted by')),
            DataColumn(label: Text('Agreed')),
          ],
          rows: _items
              .map((item) => DataRow(cells: [
                    DataCell(Text(item.acceptedAt.split('T').first)),
                    DataCell(_StatusChip(status: item.status)),
                    DataCell(
                      _hover(
                        item.caregiverHoverText,
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.caregiverDisplayLabel ?? '-'}  ${item.caregiverName}'),
                            PhoneWithContact(phone: item.caregiverPhone),
                          ],
                        ),
                      ),
                      onTap: () => _openCaregiver(item),
                    ),
                    // The job: hover for its details, click to open it.
                    DataCell(
                      _hover(item.jobHoverText, _linkText(item.jobLabel, key: Key('accepted-job-${item.applicationId}'))),
                      onTap: () => _openJob(item),
                    ),
                    DataCell(Text('${item.posterName ?? '-'}\n${item.posterDisplayLabel ?? ''}'.trim())),
                    // Who accepted: hover for their details, click to open a patient's / organisation's profile.
                    DataCell(
                      _hover(
                        item.acceptedByHoverText,
                        item.acceptedByHasProfile
                            ? _linkText(_by(item), key: Key('accepted-by-${item.applicationId}'))
                            : Text(_by(item), key: Key('accepted-by-${item.applicationId}')),
                      ),
                      onTap: item.acceptedByHasProfile ? () => _openAcceptedBy(item) : null,
                    ),
                    DataCell(Text(_agreed(item))),
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

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600),
      ),
    );
  }
}
