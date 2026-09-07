import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/audit_log_models.dart';
import '../data/audit_logs_repository.dart';

/// Self-contained "search this account's own audit trail" section, embedded
/// in IndividualDetailScreen/OrganisationDetailScreen/CaregiverDetailScreen's
/// own audit history — a fixed [targetUserId] filter plus admin-controlled
/// search text/action/date-range, so admin can narrow a busy account's
/// history down to e.g. one job id or one kind of decision to correlate
/// related entries, instead of scanning a flat capped list. Owns its own
/// fetch/loading/error/pagination state; callers supply [itemBuilder] since
/// each screen renders one entry differently (a Row for individual/
/// organisation, a Card for caregiver) — this widget only owns the filter
/// bar, the list scaffolding, and the pager around it.
class ScopedAuditHistorySection extends ConsumerStatefulWidget {
  final String targetUserId;
  final Widget Function(BuildContext context, AuditLogEntry entry) itemBuilder;

  const ScopedAuditHistorySection({
    super.key,
    required this.targetUserId,
    required this.itemBuilder,
  });

  @override
  ConsumerState<ScopedAuditHistorySection> createState() =>
      ScopedAuditHistorySectionState();
}

class ScopedAuditHistorySectionState
    extends ConsumerState<ScopedAuditHistorySection> {
  final searchController = TextEditingController();
  String? action;
  DateTime? fromDate;
  DateTime? toDate;
  int _page = 1;

  List<AuditLogEntry> items = [];
  PaginationMeta? meta;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final result = await ref.read(auditLogsRepositoryProvider).list(
            AuditLogListFilters(
              targetUserId: widget.targetUserId,
              action: action,
              fromDate: fromDate?.toIso8601String().split('T').first,
              toDate: toDate?.toIso8601String().split('T').first,
              search: searchController.text.trim(),
              page: _page,
            ),
          );
      if (mounted) {
        setState(() {
          items = result.items;
          meta = result.meta;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => errorMessage = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void applyFilters() {
    _page = 1;
    load();
  }

  void clearFilters() {
    searchController.clear();
    setState(() {
      action = null;
      fromDate = null;
      toDate = null;
    });
    applyFilters();
  }

  bool get hasActiveFilters =>
      searchController.text.trim().isNotEmpty ||
      action != null ||
      fromDate != null ||
      toDate != null;

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      initialDate: (isFrom ? fromDate : toDate) ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() => isFrom ? fromDate = picked : toDate = picked);
      applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterRow(),
        const SizedBox(height: AppSpacing.sm),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: VitaLoadingIndicator()),
          )
        else if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(errorMessage!, style: const TextStyle(color: AppColors.error)),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(hasActiveFilters
                ? 'No activity matches these filters.'
                : 'No actions recorded for this account yet.'),
          )
        else
          ...items.map((entry) => widget.itemBuilder(context, entry)),
        if (meta != null && meta!.totalPages > 1) _buildPager(),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Search',
              hintText: 'Job id, action, reason...',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onSubmitted: (_) => applyFilters(),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: action,
            decoration: const InputDecoration(
                labelText: 'Action', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All actions')),
              ...AuditAction.all
                  .map((a) => DropdownMenuItem<String?>(value: a, child: Text(a))),
            ],
            onChanged: (value) {
              setState(() => action = value);
              applyFilters();
            },
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isFrom: true),
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(fromDate == null ? 'From date' : fromDate!.toIso8601String().split('T').first),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickDate(isFrom: false),
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(toDate == null ? 'To date' : toDate!.toIso8601String().split('T').first),
        ),
        ElevatedButton(onPressed: applyFilters, child: const Text('Search')),
        if (hasActiveFilters) TextButton(onPressed: clearFilters, child: const Text('Clear')),
      ],
    );
  }

  Widget _buildPager() {
    final m = meta!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        children: [
          Text('Page ${m.page} of ${m.totalPages} (${m.total} total)',
              style: const TextStyle(fontSize: AppTypography.small, color: AppColors.textSecondary)),
          IconButton(
            onPressed: m.page > 1
                ? () {
                    _page = m.page - 1;
                    load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: m.page < m.totalPages
                ? () {
                    _page = m.page + 1;
                    load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
