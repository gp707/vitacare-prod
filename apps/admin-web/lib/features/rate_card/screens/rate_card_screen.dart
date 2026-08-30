import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/rate_card_repository.dart';

/// Lets an admin edit the salary-guidance grid shown behind a persistent
/// app-bar icon on caregiver-app (NurseJobs) and nursenow-app's Individual
/// screens — never shown to Organisation accounts. The grid shape (3
/// columns x 3 rows) is fixed; every label and cell is free-text editable.
class RateCardScreen extends ConsumerStatefulWidget {
  const RateCardScreen({super.key});

  @override
  ConsumerState<RateCardScreen> createState() => _RateCardScreenState();
}

class _RateCardScreenState extends ConsumerState<RateCardScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  String? _updatedByName;
  String? _updatedAt;

  late TextEditingController _titleController;
  late List<TextEditingController> _columnControllers;
  late List<TextEditingController> _rowControllers;
  late List<List<TextEditingController>> _cellControllers;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _columnControllers = List.generate(3, (_) => TextEditingController());
    _rowControllers = List.generate(3, (_) => TextEditingController());
    _cellControllers = List.generate(3, (_) => List.generate(3, (_) => TextEditingController()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _columnControllers) {
      c.dispose();
    }
    for (final c in _rowControllers) {
      c.dispose();
    }
    for (final row in _cellControllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final withUpdater = await ref.read(rateCardRepositoryProvider).get();
      if (!mounted) return;
      _applyToControllers(withUpdater);
      setState(() {
        _updatedByName = withUpdater.updatedByName;
        _updatedAt = withUpdater.updatedAt;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyToControllers(RateCardWithUpdater withUpdater) {
    final rateCard = withUpdater.rateCard;
    _titleController.text = rateCard.title;
    for (var i = 0; i < 3; i++) {
      _columnControllers[i].text = rateCard.columnLabels[i];
      _rowControllers[i].text = rateCard.rowLabels[i];
      for (var j = 0; j < 3; j++) {
        _cellControllers[i][j].text = rateCard.cells[i][j];
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final rateCard = RateCardModel(
        title: _titleController.text.trim(),
        columnLabels: _columnControllers.map((c) => c.text.trim()).toList(),
        rowLabels: _rowControllers.map((c) => c.text.trim()).toList(),
        cells: _cellControllers
            .map((row) => row.map((c) => c.text.trim()).toList())
            .toList(),
      );
      await ref.read(rateCardRepositoryProvider).update(rateCard);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rate card saved')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.rateCard,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rate Card',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Salary guidance shown to caregivers (NurseJobs) and patients/families '
                '(NurseNow) behind an icon on every screen. Not shown to hospitals/rehabs/clinics.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildForm(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) ...[
          Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: AppSpacing.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _buildGrid(),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_updatedByName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Last updated by $_updatedByName${_updatedAt != null ? ' on $_updatedAt' : ''}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  static const _cellWidth = 220.0;
  static const _rowLabelWidth = 260.0;

  Widget _buildGrid() {
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(_rowLabelWidth),
        for (var i = 1; i <= 3; i++) i: const FixedColumnWidth(_cellWidth),
      },
      border: TableBorder.all(color: AppColors.border),
      children: [
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Text('Caregiver Tier \\ Care Type', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var col = 0; col < 3; col++)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: TextField(
                  controller: _columnControllers[col],
                  decoration: const InputDecoration(labelText: 'Column label'),
                ),
              ),
          ],
        ),
        for (var row = 0; row < 3; row++)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: TextField(
                  controller: _rowControllers[row],
                  decoration: const InputDecoration(labelText: 'Row label'),
                  maxLines: 2,
                ),
              ),
              for (var col = 0; col < 3; col++)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: TextField(
                    controller: _cellControllers[row][col],
                    decoration: const InputDecoration(labelText: 'Rate'),
                    maxLines: 2,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
