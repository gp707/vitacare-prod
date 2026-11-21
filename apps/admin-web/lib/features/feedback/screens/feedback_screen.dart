import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/hide_for_read_only.dart';
import '../../../shared/widgets/vita_list_card.dart';
import '../data/admin_feedback_repository.dart';
import '../widgets/edit_feedback_dialog.dart';

/// Feedback patients/families and caregivers leave each other after they have worked
/// together: 1-5 stars and a short comment, one per person per engagement, final once
/// sent. A patient sees their own; a caregiver sees their own and the family's STAR RATING
/// about them (never the comment); a patient never sees a caregiver's feedback. This is the one
/// place everything — every rating and comment — can be read, and the one place a feedback can be
/// corrected (full admins only; a read-only admin can read but not edit).
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  int _page = 1;
  String? _authorRole;
  int? _rating;
  final _searchController = TextEditingController();
  List<AdminFeedbackItem> _items = [];
  PaginationMeta? _meta;
  bool _loading = true;
  String? _errorMessage;

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
      final result = await ref.read(adminFeedbackRepositoryProvider).list(
            page: _page,
            authorRole: _authorRole,
            rating: _rating,
            search: _searchController.text.trim(),
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

  /// Admin corrects a feedback (rating and/or comment); reloads the list when saved.
  Future<void> _edit(AdminFeedbackItem item) async {
    final saved = await showEditFeedbackDialog(
      context,
      item: item,
      onSave: (rating, comment) =>
          ref.read(adminFeedbackRepositoryProvider).update(item.id, rating: rating, comment: comment),
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback updated.')));
      await _load();
    }
  }

  void _applyFilters() {
    _page = 1;
    _load();
  }

  void _openCaregiver(AdminFeedbackItem item) =>
      Navigator.of(context).pushNamed('/caregiver-detail', arguments: item.caregiverProfileId);

  void _openPatient(AdminFeedbackItem item) {
    final id = item.patientUserId;
    if (id != null) Navigator.of(context).pushNamed('/individual-detail', arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.feedback,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Feedback', style: TextStyle(fontSize: AppTypography.display, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Feedback patients/families and caregivers left each other after working together. '
                'Overall for the whole engagement, written once and final.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('feedback-filter-direction'),
                      isExpanded: true,
                      initialValue: _authorRole,
                      decoration: const InputDecoration(labelText: 'Who wrote it', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('Everyone')),
                        DropdownMenuItem<String?>(value: 'individual', child: Text('Patient/Family about caregiver')),
                        DropdownMenuItem<String?>(value: 'caregiver', child: Text('Caregiver about family')),
                      ],
                      onChanged: (value) {
                        setState(() => _authorRole = value);
                        _applyFilters();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int?>(
                      key: const Key('feedback-filter-rating'),
                      isExpanded: true,
                      initialValue: _rating,
                      decoration: const InputDecoration(labelText: 'Stars', border: OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Any')),
                        for (var i = 5; i >= 1; i--) DropdownMenuItem<int?>(value: i, child: Text('$i star${i == 1 ? '' : 's'}')),
                      ],
                      onChanged: (value) {
                        setState(() => _rating = value);
                        _applyFilters();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      key: const Key('feedback-search'),
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search name, phone, NUR-/PAT- id or comment',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _applyFilters(),
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

  Widget _stars(int rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= rating ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade700),
        ],
      );

  String _fromLabel(AdminFeedbackItem item) => item.byPatient
      ? '${item.patientLabel} ${item.patientName ?? ''}'.trim()
      : '${item.caregiverLabel} ${item.caregiverName ?? ''}'.trim();

  String _toLabel(AdminFeedbackItem item) => item.byPatient
      ? '${item.caregiverLabel} ${item.caregiverName ?? ''}'.trim()
      : '${item.patientLabel} ${item.patientName ?? ''}'.trim();

  Widget _buildList() {
    if (_items.isEmpty) {
      return const Center(child: Text('No feedback matches this filter.', key: Key('feedback-empty')));
    }
    if (context.isMobile) {
      return ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return VitaListCard(
            title: Text('${_fromLabel(item)} → ${_toLabel(item)}'),
            trailing: _stars(item.rating),
            onTap: () => item.byPatient ? _openCaregiver(item) : _openPatient(item),
            fields: [
              VitaListCard.kv('Date', item.createdAt.split('T').first),
              if (item.jobLabel != null) VitaListCard.kv('Job', item.jobLabel!),
              if (item.comment != null) VitaListCard.kv('Comment', item.comment!),
              HideForReadOnly(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: Key('edit-feedback-${item.id}'),
                    onPressed: () => _edit(item),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                ),
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
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('From')),
            DataColumn(label: Text('About')),
            DataColumn(label: Text('Stars')),
            DataColumn(label: Text('Comment')),
            DataColumn(label: Text('Job')),
            DataColumn(label: Text('')),
          ],
          rows: _items
              .map((item) => DataRow(cells: [
                    DataCell(Text(item.createdAt.split('T').first)),
                    DataCell(
                      Text(_fromLabel(item)),
                      onTap: () => item.byPatient ? _openPatient(item) : _openCaregiver(item),
                    ),
                    DataCell(
                      Text(_toLabel(item)),
                      onTap: () => item.byPatient ? _openCaregiver(item) : _openPatient(item),
                    ),
                    DataCell(_stars(item.rating)),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(item.comment ?? '-', softWrap: true),
                    )),
                    DataCell(Text(item.jobLabel ?? '-')),
                    DataCell(HideForReadOnly(
                      child: IconButton(
                        key: Key('edit-feedback-${item.id}'),
                        tooltip: 'Edit this feedback',
                        onPressed: () => _edit(item),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
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
