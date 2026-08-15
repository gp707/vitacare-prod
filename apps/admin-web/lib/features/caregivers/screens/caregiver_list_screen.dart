import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/admin_caregivers_repository.dart';
import '../data/admin_caregiver_models.dart';

class CaregiverListScreen extends ConsumerStatefulWidget {
  final String? initialStatus;

  const CaregiverListScreen({super.key, this.initialStatus});

  @override
  ConsumerState<CaregiverListScreen> createState() => _CaregiverListScreenState();
}

class _CaregiverListScreenState extends ConsumerState<CaregiverListScreen> {
  final _searchController = TextEditingController();
  String? _status;
  String? _qualification;
  int _page = 1;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(adminCaregiversRepositoryProvider).list(
            CaregiverListFilters(
              search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
              status: _status,
              qualification: _qualification,
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

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.caregivers,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Caregivers', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.md),
              _buildFilterPanel(),
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

  Widget _buildFilterPanel() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search name or phone',
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
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
              ...VerificationStatus.all.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
            ],
            onChanged: (value) => setState(() => _status = value),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _qualification,
            decoration:
                const InputDecoration(labelText: 'Qualification', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All qualifications')),
              ...Qualification.all.map(
                  (q) => DropdownMenuItem<String?>(value: q, child: Text(Qualification.displayNames[q] ?? q))),
            ],
            onChanged: (value) => setState(() => _qualification = value),
          ),
        ),
        ElevatedButton(onPressed: _applyFilters, child: const Text('Apply Filters')),
      ],
    );
  }

  Widget _buildTable() {
    if (_items.isEmpty) {
      return const Center(child: Text('No caregivers match these filters.'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Phone')),
            DataColumn(label: Text('Gender')),
            DataColumn(label: Text('Age')),
            DataColumn(label: Text('Qualification')),
            DataColumn(label: Text('Service Modes')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Registered')),
          ],
          rows: _items
              .map(
                (item) => DataRow(
                  onSelectChanged: (_) =>
                      Navigator.of(context).pushNamed('/caregiver-detail', arguments: item.profileId),
                  cells: [
                    DataCell(Text(item.fullName)),
                    DataCell(Text(item.phone)),
                    DataCell(Text(item.gender)),
                    DataCell(Text('${item.age}')),
                    DataCell(Text(Qualification.displayNames[item.highestQualification] ?? item.highestQualification ?? '-')),
                    DataCell(Text(item.serviceModes.join(', '))),
                    DataCell(VitaStatusBadge(status: item.verificationStatus)),
                    DataCell(Text(item.createdAt.split('T').first)),
                  ],
                ),
              )
              .toList(),
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
