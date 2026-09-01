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
/// (not cached) since it's cheap and rarely changes mid-session. Shows
/// both the daily and monthly cards stacked in one dialog — admin
/// maintains them as 2 separate rows, never just one merged grid.
class RateCardButton extends ConsumerWidget {
  const RateCardButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A bare rupee icon read as unclear/ambiguous — spelling out "Rate
    // Card" as a visible label removes any doubt about what it opens.
    // Built from ElevatedButton (not ElevatedButton.icon, which forces an
    // 8px icon-label gap that doesn't fit this AppBar's already-tight
    // budget) with a hand-built Row so the icon-label gap can shrink to 1px
    // — shares AppBar space with WhatsApp help and other actions, same
    // reasoning as WhatsAppHelpButton's own compact styling. Wrapped in a
    // right-margin Padding so it never sits flush against a neighboring
    // button or the screen edge.
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ElevatedButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => _RateCardDialog(repository: ref.read(rateCardRepositoryProvider)),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.currency_rupee, size: 12),
            SizedBox(width: 1),
            Text('Rate Card', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        ),
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
  List<RateCardModel>? _rateCards;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rateCards = await widget.repository.get();
      if (mounted) setState(() => _rateCards = rateCards);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load salary guidance. Please try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sized off the actual device width (not a fixed 400px) and paired with
    // a tight insetPadding, so the dialog claims nearly the full screen on
    // a phone — combined with _RateCardTable's flexible (not fixed-pixel)
    // column widths below, both rate cards fit and read fully without
    // needing horizontal scrolling, and typically without vertical
    // scrolling either (each card is just a title + a 2-row table). The
    // outer SingleChildScrollView stays only as a safety net for an
    // unusually long admin-typed cell value on a short screen.
    final dialogWidth = (MediaQuery.of(context).size.width - 32).clamp(280.0, 560.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Salary Guidance'),
      content: SizedBox(
        width: dialogWidth,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: VitaLoadingIndicator()),
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: AppColors.error))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _rateCards!.length; i++) ...[
                          if (i > 0) const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            child: Divider(height: 1),
                          ),
                          Text(_rateCards![i].title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: AppSpacing.xs),
                          _RateCardTable(rateCard: _rateCards![i]),
                        ],
                      ],
                    ),
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

  @override
  Widget build(BuildContext context) {
    return Table(
      // Flexible, proportional column widths (not fixed pixels) so the
      // table always fits within whatever width the dialog actually has —
      // long cell text wraps onto multiple lines instead of forcing
      // horizontal scrolling. The row-label column gets a smaller share
      // since it only ever holds the short "Care" label, unlike the data
      // columns which can carry a whole sentence.
      columnWidths: const {
        0: FlexColumnWidth(0.7),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: AppColors.border),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (final label in rateCard.columnLabels)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
          ],
        ),
        for (var i = 0; i < rateCard.rowLabels.length; i++)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Text(rateCard.rowLabels[i], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              for (final cell in rateCard.cells[i])
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Text(cell, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
      ],
    );
  }
}
