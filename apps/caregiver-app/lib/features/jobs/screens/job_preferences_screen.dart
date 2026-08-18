import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

/// Reachable via the gear icon on the Jobs tab — every preference that
/// controls which jobs show up on that tab, all in one place. Editable
/// anytime, no admin approval needed, never affects verification_status
/// (same self-edit mechanics as everything on Edit Profile, just scoped to
/// job search rather than personal/document info).
class JobPreferencesScreen extends ConsumerStatefulWidget {
  const JobPreferencesScreen({super.key});

  @override
  ConsumerState<JobPreferencesScreen> createState() => _JobPreferencesScreenState();
}

class _JobPreferencesScreenState extends ConsumerState<JobPreferencesScreen> {
  CaregiverProfileModel? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> _preferredCities = [];
  List<String> _preferredDutyTypes = [];
  final _minSalaryPerDayController = TextEditingController();
  final _minSalaryPerMonthController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minSalaryPerDayController.dispose();
    _minSalaryPerMonthController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ref.read(profileRepositoryProvider).getProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _preferredCities = List.from(profile.preferredCities);
      _preferredDutyTypes = List.from(profile.preferredDutyTypes);
      _minSalaryPerDayController.text = profile.minSalaryPerDay?.toString() ?? '';
      _minSalaryPerMonthController.text = profile.minSalaryPerMonth?.toString() ?? '';
      _loading = false;
    });
  }

  bool _listChanged(List<String> next, List<String> previous) {
    final sortedNext = [...next]..sort();
    final sortedPrevious = [...previous]..sort();
    return sortedNext.join(',') != sortedPrevious.join(',');
  }

  Future<void> _save() async {
    final profile = _profile!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final minSalaryPerDayText = _minSalaryPerDayController.text.trim();
      int? minSalaryPerDay;
      if (minSalaryPerDayText.isNotEmpty) {
        minSalaryPerDay = int.tryParse(minSalaryPerDayText);
        if (minSalaryPerDay == null || minSalaryPerDay < 1) {
          setState(() => _error = 'Minimum salary per day must be a positive number');
          return;
        }
      }
      final minSalaryPerMonthText = _minSalaryPerMonthController.text.trim();
      int? minSalaryPerMonth;
      if (minSalaryPerMonthText.isNotEmpty) {
        minSalaryPerMonth = int.tryParse(minSalaryPerMonthText);
        if (minSalaryPerMonth == null || minSalaryPerMonth < 1) {
          setState(() => _error = 'Minimum salary per month must be a positive number');
          return;
        }
      }

      await ref.read(profileRepositoryProvider).editProfile(
            preferredCities:
                _listChanged(_preferredCities, profile.preferredCities) ? _preferredCities : null,
            preferredDutyTypes: _listChanged(_preferredDutyTypes, profile.preferredDutyTypes)
                ? _preferredDutyTypes
                : null,
            minSalaryPerDay: minSalaryPerDay != profile.minSalaryPerDay ? minSalaryPerDay : null,
            minSalaryPerMonth:
                minSalaryPerMonth != profile.minSalaryPerMonth ? minSalaryPerMonth : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                      "These only control which jobs you see on the Jobs tab. Change them anytime — no admin approval needed, and it never affects your verification status. Leave anything blank/unselected for no preference on that filter.",
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Preferred City (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  VitaMultiSelectChips(
                    options: City.all,
                    labels: City.displayNames,
                    selected: _preferredCities,
                    onChanged: (next) => setState(() => _preferredCities = next),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Preferred Shift/Duty Type (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  VitaMultiSelectChips(
                    options: DutyType.all,
                    labels: DutyType.displayNames,
                    selected: _preferredDutyTypes,
                    onChanged: (next) => setState(() => _preferredDutyTypes = next),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _minSalaryPerDayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minimum Salary — ₹/day (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _minSalaryPerMonthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minimum Salary — ₹/month (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
      ),
    );
  }
}
