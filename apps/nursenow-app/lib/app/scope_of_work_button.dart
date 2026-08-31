import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/providers.dart';
import '../core/scope_of_work/scope_of_work_repository.dart';

/// Per-requirement entry point (not an AppBar action like RateCardButton/
/// WhatsAppHelpButton — this lives inline on a requirement's detail view,
/// since which tier it opens depends on that specific requirement's
/// care_receiver) showing exactly which caregiving tasks a posted
/// requirement involves. Which tier is derived from [careReceiver] via
/// [deriveCareTier] — never manually picked — and the popup shows only
/// that tier's bullets, stacked cumulatively with every tier below it,
/// never the full admin-editable table. Individual postings reuse the same
/// jobs/care_receivers backend tables an admin-posted job does, so this
/// renders identically to what a caregiver sees on the same job in
/// caregiver-app (NurseJobs) — same derivation, same admin-editable
/// content, same public GET /scope-of-work endpoint.
class ScopeOfWorkButton extends ConsumerWidget {
  final CareReceiverModel careReceiver;

  const ScopeOfWorkButton({super.key, required this.careReceiver});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = deriveCareTier(careReceiver);
    return OutlinedButton.icon(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => _ScopeOfWorkDialog(
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
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ScopeOfWorkDialog extends StatefulWidget {
  final String tier;
  final ScopeOfWorkRepository repository;

  const _ScopeOfWorkDialog({required this.tier, required this.repository});

  @override
  State<_ScopeOfWorkDialog> createState() => _ScopeOfWorkDialogState();
}

class _ScopeOfWorkDialogState extends State<_ScopeOfWorkDialog> {
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
      title: Text(CareTier.displayNames[widget.tier] ?? widget.tier),
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
                                const Text('•  '),
                                Expanded(child: Text(bullet)),
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
