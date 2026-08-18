import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/individual_repository.dart';

/// Same About Patient / location / duty-type / language-preference fields
/// as admin's job-posting form — minus Frequency of Care and Salary, which
/// an admin sets later on approval. Creates a pending_review requirement.
class PostRequirementScreen extends ConsumerStatefulWidget {
  const PostRequirementScreen({super.key});

  @override
  ConsumerState<PostRequirementScreen> createState() => _PostRequirementScreenState();
}

class _PostRequirementScreenState extends ConsumerState<PostRequirementScreen> {
  final _ageController = TextEditingController();
  String? _gender;
  final _weightController = TextEditingController();
  String? _mobility;
  String? _communication;
  String? _feedingType;
  final List<String> _medicalAssistance = [];
  bool _hasMedicalCondition = false;
  final List<String> _medicalConditions = [];
  final _medicalConditionOtherController = TextEditingController();
  final List<String> _toiletAssistance = [];
  final _toiletAssistanceOtherController = TextEditingController();
  bool _requiresVitalMonitoring = false;
  final List<String> _vitalMonitoringTypes = [];

  String? _city;
  final _areaController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _dutyType;
  final _startDateController = TextEditingController();
  final List<String> _languages = [];
  String? _preferredGender;
  String? _preferredReligion;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _areaController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      _startDateController.text = picked.toIso8601String().split('T').first;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final age = int.tryParse(_ageController.text.trim());
      final weight = int.tryParse(_weightController.text.trim());
      if (age == null || _gender == null || weight == null) {
        setState(() => _error = "Patient's age, gender, and weight are required");
        return;
      }
      if (_city == null || _areaController.text.trim().isEmpty) {
        setState(() => _error = 'City and area are required');
        return;
      }
      if (_dutyType == null) {
        setState(() => _error = 'Select the hours of care needed');
        return;
      }
      if (_startDateController.text.trim().isEmpty) {
        setState(() => _error = 'Select a preferred start date');
        return;
      }
      if (_languages.isEmpty) {
        setState(() => _error = 'Select at least one language');
        return;
      }

      await ref.read(individualRepositoryProvider).createRequirement(
            careReceiver: CareReceiverInput(
              age: age,
              gender: _gender!,
              weightKg: weight,
              mobility: _mobility,
              communication: _communication,
              feedingType: _feedingType,
              medicalAssistance: _medicalAssistance.isEmpty ? null : _medicalAssistance,
              hasMedicalCondition: _hasMedicalCondition,
              medicalConditions: _hasMedicalCondition ? _medicalConditions : null,
              medicalConditionOther: _medicalConditionOtherController.text.trim(),
              toiletAssistance: _toiletAssistance.isEmpty ? null : _toiletAssistance,
              toiletAssistanceOther: _toiletAssistanceOtherController.text.trim(),
              requiresVitalMonitoring: _requiresVitalMonitoring,
              vitalMonitoringTypes: _requiresVitalMonitoring ? _vitalMonitoringTypes : null,
            ),
            city: _city!,
            area: _areaController.text.trim(),
            description: _descriptionController.text.trim(),
            dutyType: _dutyType!,
            startDate: _startDateController.text.trim(),
            languages: _languages,
            preferredGender: _preferredGender,
            preferredReligion: _preferredReligion,
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
      appBar: AppBar(title: const Text('Post a Requirement')),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: const Text(
                "An admin reviews every new requirement and sets the frequency of care and salary before it goes live and caregivers can see it.",
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('About Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Patient's Age", border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _gender,
              decoration: const InputDecoration(labelText: "Patient's Gender", border: OutlineInputBorder()),
              items: Gender.all
                  .map((g) => DropdownMenuItem(value: g, child: Text(_capitalize(g))))
                  .toList(),
              onChanged: (value) => setState(() => _gender = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Patient's Weight (kg)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _mobility,
              decoration: const InputDecoration(labelText: 'Mobility (optional)', border: OutlineInputBorder()),
              items: Mobility.all
                  .map((m) => DropdownMenuItem(value: m, child: Text(Mobility.displayNames[m] ?? m)))
                  .toList(),
              onChanged: (value) => setState(() => _mobility = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _communication,
              decoration: const InputDecoration(labelText: 'Communication (optional)', border: OutlineInputBorder()),
              items: Communication.all
                  .map((c) => DropdownMenuItem(value: c, child: Text(Communication.displayNames[c] ?? c)))
                  .toList(),
              onChanged: (value) => setState(() => _communication = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _feedingType,
              decoration: const InputDecoration(labelText: 'Feeding (optional)', border: OutlineInputBorder()),
              items: FeedingType.all
                  .map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f)))
                  .toList(),
              onChanged: (value) => setState(() => _feedingType = value),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Medicine (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: MedicalAssistance.all,
              labels: MedicalAssistance.displayNames,
              selected: _medicalAssistance,
              onChanged: (next) => setState(() {
                _medicalAssistance
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Has a medical condition?'),
              value: _hasMedicalCondition,
              onChanged: (value) => setState(() => _hasMedicalCondition = value),
            ),
            if (_hasMedicalCondition) ...[
              VitaMultiSelectChips(
                options: MedicalCondition.all,
                labels: MedicalCondition.displayNames,
                selected: _medicalConditions,
                onChanged: (next) => setState(() {
                  _medicalConditions
                    ..clear()
                    ..addAll(next);
                }),
              ),
              if (_medicalConditions.contains(MedicalCondition.other)) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _medicalConditionOtherController,
                  decoration: const InputDecoration(
                    labelText: 'Please describe the other condition',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            const Text('Toilet Assistance (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: ToiletAssistance.all,
              labels: ToiletAssistance.displayNames,
              selected: _toiletAssistance,
              onChanged: (next) => setState(() {
                _toiletAssistance
                  ..clear()
                  ..addAll(next);
              }),
            ),
            if (_toiletAssistance.contains(ToiletAssistance.others)) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _toiletAssistanceOtherController,
                decoration: const InputDecoration(
                  labelText: 'Please describe the other toilet assistance',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is regular vital monitoring required?'),
              value: _requiresVitalMonitoring,
              onChanged: (value) => setState(() => _requiresVitalMonitoring = value),
            ),
            if (_requiresVitalMonitoring)
              VitaMultiSelectChips(
                options: VitalMonitoringType.all,
                labels: VitalMonitoringType.displayNames,
                selected: _vitalMonitoringTypes,
                onChanged: (next) => setState(() {
                  _vitalMonitoringTypes
                    ..clear()
                    ..addAll(next);
                }),
              ),
            const SizedBox(height: AppSpacing.xl),
            const Text('Job Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _city,
              decoration: const InputDecoration(labelText: 'City (Mandatory)', border: OutlineInputBorder()),
              items: City.all.map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c))).toList(),
              onChanged: (value) => setState(() => _city = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(labelText: 'Area (Mandatory)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('About Nurse/Caregiver Requirement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _dutyType,
              decoration: const InputDecoration(labelText: 'Hours Care Needed (Mandatory)', border: OutlineInputBorder()),
              items: DutyType.all.map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d))).toList(),
              onChanged: (value) => setState(() => _dutyType = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _startDateController,
              readOnly: true,
              onTap: _pickStartDate,
              decoration: const InputDecoration(
                labelText: 'Preferred Start Date (Mandatory)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Language Preference (Mandatory)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            VitaMultiSelectChips(
              options: Language.all,
              labels: Language.displayNames,
              selected: _languages,
              onChanged: (next) => setState(() {
                _languages
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _preferredGender,
              decoration: const InputDecoration(labelText: 'Preferred Caregiver Gender', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('No preference')),
                DropdownMenuItem(value: Gender.male, child: Text('Male')),
                DropdownMenuItem(value: Gender.female, child: Text('Female')),
              ],
              onChanged: (value) => setState(() => _preferredGender = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _preferredReligion,
              decoration: const InputDecoration(labelText: 'Preferred Caregiver Religion', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('No preference')),
                ...[Religion.hindu, Religion.muslim, Religion.christian]
                    .map((r) => DropdownMenuItem(value: r, child: Text(_capitalize(r)))),
              ],
              onChanged: (value) => setState(() => _preferredReligion = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'More details you want to share about patient (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit for Review'),
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
