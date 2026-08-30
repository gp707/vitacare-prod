import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/providers.dart';
import '../core/rate_card/rate_card_repository.dart';

/// Persistent salary-guidance entry point — shown in every main screen's
/// AppBar for an Individual (patient/family) session, same placement
/// convention as WhatsAppHelpButton. Deliberately NOT shown on Organisation
/// (hospital/rehab/clinic) screens — these guidelines don't apply to
/// institutional bulk hiring, see CLAUDE.md. Fetched fresh on every tap
/// (not cached) since it's cheap and rarely changes mid-session.
class RateCardButton extends ConsumerWidget {
  const RateCardButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compact constraints/padding — shares AppBar space with WhatsApp help
    // and other actions, same reasoning as WhatsAppHelpButton's own styling.
    return IconButton(
      icon: const Icon(Icons.currency_rupee, size: 20),
      tooltip: 'Salary Guidance',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      onPressed: () => showDialog(
        context: context,
        builder: (_) => _RateCardDialog(repository: ref.read(rateCardRepositoryProvider)),
      ),
    );
  }
}

class _RateCardDialog extends StatefulWidget {
  final RateCardRepository repository;

  const _RateCardDialog({required this.repository});

  @override
  State<_RateCardDialog> createState() => _RateCardDialogState();
}

class _RateCardDialogState extends State<_RateCardDialog> {
  RateCardModel? _rateCard;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rateCard = await widget.repository.get();
      if (mounted) setState(() => _rateCard = rateCard);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load salary guidance. Please try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_rateCard?.title ?? 'Salary Guidance'),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: VitaLoadingIndicator()),
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppColors.error))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _RateCardTable(rateCard: _rateCard!),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _RateCardTable extends StatelessWidget {
  final RateCardModel rateCard;

  const _RateCardTable({required this.rateCard});

  static const _rowLabelWidth = 140.0;
  static const _cellWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    return Table(
      // Table has no intrinsic width of its own — without explicit
      // columnWidths it divides whatever width its parent gives it (here,
      // the dialog's fixed content width) evenly across every column,
      // collapsing each one to a sliver too narrow to hold real text and
      // wrapping it one character per line. The outer horizontal
      // SingleChildScrollView only helps once the Table itself claims a
      // real width via fixed columnWidths.
      columnWidths: const {
        0: FixedColumnWidth(_rowLabelWidth),
        1: FixedColumnWidth(_cellWidth),
        2: FixedColumnWidth(_cellWidth),
        3: FixedColumnWidth(_cellWidth),
      },
      border: TableBorder.all(color: AppColors.border),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox(width: 140),
            for (final label in rateCard.columnLabels)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        for (var i = 0; i < rateCard.rowLabels.length; i++)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(rateCard.rowLabels[i], style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final cell in rateCard.cells[i])
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(cell),
                ),
            ],
          ),
      ],
    );
  }
}
