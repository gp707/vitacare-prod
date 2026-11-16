import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import 'salary_cycle_tile.dart';

/// "Salary history" on a Selected job: every 14-day cycle newest first, each with
/// its dates, rate, leave days, calculation and whether (and when) the family paid
/// it. Loaded the first time it is opened. Read-only.
class SalaryHistory extends StatefulWidget {
  final Future<List<SalaryCycleModel>> Function() load;

  const SalaryHistory({super.key, required this.load});

  @override
  State<SalaryHistory> createState() => _SalaryHistoryState();
}

class _SalaryHistoryState extends State<SalaryHistory> {
  bool _open = false;
  bool _loading = false;
  String? _error;
  List<SalaryCycleModel>? _cycles;

  Future<void> _toggle() async {
    setState(() => _open = !_open);
    if (_open) await _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cycles = await widget.load();
      if (mounted) setState(() => _cycles = cycles);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the salary history.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycles = _cycles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('salary-history-toggle'),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.history, size: 18),
                const SizedBox(width: AppSpacing.xs),
                const Expanded(child: Text('Salary history', style: TextStyle(fontWeight: FontWeight.bold))),
                Icon(_open ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_open) ...[
          if (_loading) const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: VitaLoadingIndicator())),
          if (_error != null)
            Text(_error!, key: const Key('salary-history-error'), style: const TextStyle(color: AppColors.error)),
          if (!_loading && cycles != null && cycles.isEmpty)
            const Text(
              'No salary cycles yet. The first one ends 14 days after the cycle start date.',
              key: Key('salary-history-empty'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          if (cycles != null)
            for (final cycle in cycles) ...[
              const SizedBox(height: AppSpacing.sm),
              SalaryCycleTile(cycle: cycle),
            ],
        ],
      ],
    );
  }
}
