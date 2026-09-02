import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../jobs/widgets/scope_of_work_button.dart' show tierIcon;
import '../data/rate_card_repository.dart';

/// Lets an admin edit the salary-guidance grids shown behind a persistent
/// app-bar icon on caregiver-app (NurseJobs) and nursenow-app's Individual
/// screens — never shown to Organisation accounts. There are always exactly
/// 2 grids, one per frequency of care ('daily'/'monthly') — each is its own
/// independently-editable, independently-saveable section rather than one
/// combined form, since admin edits and saves them on separate occasions.
/// The grid shape (3 columns x 1 row) is fixed; every label and cell is
/// free-text editable.
class RateCardScreen extends ConsumerStatefulWidget {
  const RateCardScreen({super.key});

  @override
  ConsumerState<RateCardScreen> createState() => _RateCardScreenState();
}

class _RateCardScreenState extends ConsumerState<RateCardScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<RateCardWithUpdater>? _rateCards;

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
      final rateCards = await ref.read(rateCardRepositoryProvider).get();
      if (mounted) setState(() => _rateCards = rateCards);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
                '(NurseNow) behind an icon on every screen. Not shown to hospitals/rehabs/clinics. '
                'Daily and monthly rates are maintained separately and saved independently.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final rateCard in _rateCards!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                            child: _RateCardSection(
                              key: ValueKey(rateCard.rateCard.frequencyOfCare),
                              initial: rateCard,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateCardSection extends ConsumerStatefulWidget {
  final RateCardWithUpdater initial;

  const _RateCardSection({super.key, required this.initial});

  @override
  ConsumerState<_RateCardSection> createState() => _RateCardSectionState();
}

class _RateCardSectionState extends ConsumerState<_RateCardSection> {
  bool _saving = false;
  String? _errorMessage;
  late String? _updatedByName;
  late String? _updatedAt;

  late TextEditingController _titleController;
  late List<TextEditingController> _columnControllers;
  late List<TextEditingController> _rowControllers;
  late List<List<TextEditingController>> _cellControllers;

  String get _frequency => widget.initial.rateCard.frequencyOfCare;

  @override
  void initState() {
    super.initState();
    final rateCard = widget.initial.rateCard;
    _updatedByName = widget.initial.updatedByName;
    _updatedAt = widget.initial.updatedAt;
    _titleController = TextEditingController(text: rateCard.title);
    _columnControllers =
        List.generate(3, (i) => TextEditingController(text: rateCard.columnLabels[i]));
    _rowControllers =
        List.generate(1, (i) => TextEditingController(text: rateCard.rowLabels[i]));
    _cellControllers = List.generate(
      1,
      (i) => List.generate(3, (j) => TextEditingController(text: rateCard.cells[i][j])),
    );
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

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final rateCard = RateCardModel(
        frequencyOfCare: _frequency,
        title: _titleController.text.trim(),
        columnLabels: _columnControllers.map((c) => c.text.trim()).toList(),
        rowLabels: _rowControllers.map((c) => c.text.trim()).toList(),
        cells: _cellControllers
            .map((row) => row.map((c) => c.text.trim()).toList())
            .toList(),
      );
      final repository = ref.read(rateCardRepositoryProvider);
      await repository.update(_frequency, rateCard);
      // Re-fetch to pick up the server-set updated_by/updated_at — the
      // update endpoint itself only returns void.
      final refreshed = await repository.get();
      final own = refreshed.firstWhere((r) => r.rateCard.frequencyOfCare == _frequency);
      if (mounted) {
        setState(() {
          _updatedByName = own.updatedByName;
          _updatedAt = own.updatedAt;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${FrequencyOfCare.displayNames[_frequency]} rate card saved')),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: AppSpacing.xs),
              Text(
                FrequencyOfCare.displayNames[_frequency] ?? _frequency,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
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
      ),
    );
  }

  static const _cellWidth = 220.0;

  Widget _buildGrid() {
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      // No row-label column — with exactly one row ("Care"), a leading
      // label was redundant; _rowControllers still exists (for the
      // save payload's rowLabels, unchanged from whatever was loaded) but
      // is no longer rendered as an editable field.
      columnWidths: {
        for (var i = 0; i < 3; i++) i: const FixedColumnWidth(_cellWidth),
      },
      border: TableBorder.all(color: AppColors.border),
      children: [
        TableRow(
          children: [
            // Columns are index-matched to CareTier.all (Companion/Bedside/
            // Critical Care) by convention — see CLAUDE.md's Rate Card
            // section — so the same tier icon ScopeOfWorkButton uses is
            // shown here too, purely as a visual cue; the label itself
            // stays free text, admin can rename it to anything.
            for (var col = 0; col < 3; col++)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      col < CareTier.all.length ? tierIcon(CareTier.all[col]) : Icons.info_outline,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _columnControllers[col],
                      decoration: const InputDecoration(labelText: 'Column label'),
                    ),
                  ],
                ),
              ),
          ],
        ),
        for (var row = 0; row < 1; row++)
          TableRow(
            children: [
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
