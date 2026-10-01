import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/providers.dart';
import '../core/scope_of_work/scope_of_work_repository.dart';

/// Per-job entry point (not an AppBar action like RateCardButton/
/// WhatsAppHelpButton — this lives inline on a job card, since which tier
/// it opens depends on that specific job's care_receiver) showing exactly
/// which caregiving tasks this job involves. Which tier is derived from
/// [careReceiver] via [deriveCareTier] — never manually picked — and the
/// popup shows only that tier's bullets, stacked cumulatively with every
/// tier below it, never the full admin-editable table.
class ScopeOfWorkButton extends ConsumerWidget {
  final CareReceiverModel careReceiver;

  const ScopeOfWorkButton({super.key, required this.careReceiver});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = deriveCareTier(careReceiver);
    return OutlinedButton.icon(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => ScopeOfWorkDialog(
          tier: tier,
          repository: ref.read(scopeOfWorkRepositoryProvider),
        ),
      ),
      icon: const Icon(Icons.checklist, size: 16),
      label: const Text('Scope of Work'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: AppTypography.small, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class ScopeOfWorkDialog extends StatefulWidget {
  final String tier;
  final ScopeOfWorkRepository repository;

  const ScopeOfWorkDialog({required this.tier, required this.repository});

  @override
  State<ScopeOfWorkDialog> createState() => ScopeOfWorkDialogState();
}

class ScopeOfWorkDialogState extends State<ScopeOfWorkDialog> {
  ScopeOfWorkModel? _scopeOfWork;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scopeOfWork = await widget.repository.get();
      if (mounted) setState(() => _scopeOfWork = scopeOfWork);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load scope of work. Please try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Plain white dialog background — dark green bullet text still
      // carries the theme against it. The tier heading (title below)
      // stays black, since it was never given an explicit color.
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tierIcon(widget.tier), color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(CareTier.displayNames[widget.tier] ?? widget.tier)),
        ],
      ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final bullet in _scopeOfWork!.bulletsFor(widget.tier))
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                    child: Text(bullet,
                                        style: const TextStyle(
                                            color: AppColors.success, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
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

/// Which pictogram represents each care tier — shared visual language
/// between this dialog's title and RateCardButton's column headers (same 3
/// tiers, same icons), so a caregiver learns the mapping once. Escalates by
/// severity: a heart for companionship, a medical-services bag once nursing
/// tasks are involved, an emergency symbol once care is critical.
IconData tierIcon(String tier) {
  switch (tier) {
    case CareTier.bedsideCare:
      return Icons.medical_services;
    case CareTier.criticalCare:
      return Icons.emergency;
    case CareTier.companionCare:
    default:
      return Icons.favorite;
  }
}
