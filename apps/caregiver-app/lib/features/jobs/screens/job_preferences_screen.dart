import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/providers.dart';

/// Reachable via the gear icon on the Jobs tab. **Temporarily read-only**
/// (per explicit request, 2026-08-23) — editing is disabled for every
/// caregiver, and Preferred Shift/Duty Type + both minimum-salary fields
/// are shown as "select everything" (all 3 shifts, ₹0 minimums) regardless
/// of what's actually stored, so every caregiver effectively sees every
/// job on the Jobs tab. This is a display-only change: nothing in the
/// database is touched (an empty/null preference already matches every
/// job under the existing filter logic — see CLAUDE.md — so the forced
/// display values and the real stored data produce identical filtering
/// behavior either way). Preferred City is the one field still shown as
/// the caregiver's real stored value, just non-interactive, since this
/// request didn't ask for a forced default there. Re-enabling editing
/// later is just restoring the interactive version of this screen — no
/// data cleanup needed, since none was ever mutated.
class JobPreferencesScreen extends ConsumerStatefulWidget {
  const JobPreferencesScreen({super.key});

  @override
  ConsumerState<JobPreferencesScreen> createState() => _JobPreferencesScreenState();
}

class _JobPreferencesScreenState extends ConsumerState<JobPreferencesScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ref.read(profileRepositoryProvider).getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job Search Preferences')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: VitaLoadingIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                    ),
                    child: const Text(
                      "Editing is temporarily unavailable. Your shift and minimum salary preferences are "
                      "fixed to show you jobs of every type and salary for now, so you don't miss anything. "
                      "We'll bring editing back soon.",
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Preferred City', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: City.all
                        .map((city) => FilterChip(
                              label: Text(City.displayNames[city] ?? city),
                              selected: _profile!.preferredCities.contains(city),
                              onSelected: null,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Preferred Shift/Duty Type', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: DutyType.all
                        .map((type) => FilterChip(
                              label: Text(DutyType.displayNames[type] ?? type),
                              selected: true,
                              onSelected: null,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _ReadOnlySalaryField(label: 'Minimum Salary — ₹/day', value: '0'),
                  const SizedBox(height: AppSpacing.md),
                  const _ReadOnlySalaryField(label: 'Minimum Salary — ₹/month', value: '0'),
                ],
              ),
      ),
    );
  }
}

/// A disabled-looking `TextField` showing a fixed value — used while
/// editing is unavailable (see the class doc comment above). A plain
/// `TextField(enabled: false, controller: ...)` needs a real controller to
/// show text, which would be pointless per-build churn for a value that
/// never changes, so this just draws the same visual directly.
class _ReadOnlySalaryField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlySalaryField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), filled: true),
      child: Text(value, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
