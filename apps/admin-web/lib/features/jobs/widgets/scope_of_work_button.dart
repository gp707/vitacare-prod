import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/providers.dart';
import '../../scope_of_work/data/scope_of_work_repository.dart';

/// Lets an admin see which Scope of Work tier a job's care needs derive
/// to — the same derivation (`deriveCareTier`) and the same admin-editable
/// content a caregiver sees on this job in NurseJobs, and a patient/family
/// sees on their own posted requirement in NurseNow. Read-only: an admin
/// cannot override the derived tier here, only see it — same reasoning as
/// caregiver-app/nursenow-app's equivalent buttons (the tier is always
/// computed from the job's care_receiver, never manually assigned).
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
      // Admin's own repository hits the authenticated /admin/scope-of-work
      // endpoint (adds updated_by_name) rather than the public one the
      // mobile apps use — same underlying data either way.
      final withUpdater = await widget.repository.get();
      if (mounted) setState(() => _scopeOfWork = withUpdater.scopeOfWork);
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
