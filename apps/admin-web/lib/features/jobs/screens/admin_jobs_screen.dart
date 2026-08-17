import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/admin_jobs_repository.dart';
import '../widgets/job_detail_dialog.dart';

/// Admin posts a job built around the care receiver's needs, it's
/// broadcast to all caregivers via push, and caregivers apply/reject. This
/// screen covers post/list/close/view-applicants/accept-or-reject;
/// caregiver-facing browsing lives in apps/caregiver-app's Jobs tab.
class AdminJobsScreen extends ConsumerStatefulWidget {
  const AdminJobsScreen({super.key});

  @override
  ConsumerState<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

class _AdminJobsScreenState extends ConsumerState<AdminJobsScreen> {
  List<JobModel> _jobs = [];
  bool _loading = true;
  String? _errorMessage;

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
      final jobs = await ref.read(adminJobsRepositoryProvider).list();
      if (mounted) setState(() => _jobs = jobs);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      // A stray click outside the dialog must not silently wipe out
      // whatever the admin has already typed — only Cancel/Post do that.
      barrierDismissible: false,
      builder: (dialogContext) => const _JobFormDialog(),
    );
    if (created == true) await _load();
  }

  /// Opens the same form pre-filled with the job's full current details —
  /// doubles as "view full details" (every field is shown) and "edit"
  /// (fields are editable, Save Changes updates in place and reposts if
  /// the job was closed).
  Future<void> _openEditDialog(JobModel job) async {
    try {
      final (fullJob, _) = await ref.read(adminJobsRepositoryProvider).getDetail(job.id);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        // Same reasoning as the create dialog — don't let a stray outside
        // click discard in-progress edits.
        barrierDismissible: false,
        builder: (dialogContext) => _JobFormDialog(job: fullJob, careReceiver: fullJob.careReceiver),
      );
      if (saved == true) await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _close(JobModel job) async {
    try {
      await ref.read(adminJobsRepositoryProvider).close(job.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _remind(JobModel job) async {
    try {
      await ref.read(adminJobsRepositoryProvider).remind(job.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder sent')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _viewApplications(JobModel job) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => JobDetailDialog(jobId: job.id),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppShellSection.jobs,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Jobs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: _openCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Post New Job'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_loading)
                const Expanded(child: Center(child: VitaLoadingIndicator()))
              else if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
              else if (_jobs.isEmpty)
                const Text('No jobs posted yet.', style: TextStyle(color: AppColors.textSecondary))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _jobs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final job = _jobs[index];
                      return _JobRow(
                        job: job,
                        onClose: job.status == JobStatus.active ? () => _close(job) : null,
                        onRemind: job.status == JobStatus.active ? () => _remind(job) : null,
                        onViewApplications: () => _viewApplications(job),
                        onEdit: () => _openEditDialog(job),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class _JobRow extends StatelessWidget {
  final JobModel job;
  final VoidCallback? onClose;
  final VoidCallback? onRemind;
  final VoidCallback onViewApplications;
  final VoidCallback onEdit;

  const _JobRow({
    required this.job,
    required this.onClose,
    required this.onRemind,
    required this.onViewApplications,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job #${job.jobNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${DutyType.displayNames[job.dutyType] ?? job.dutyType} · '
                        '${City.displayNames[job.city] ?? job.city}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    VitaStatusBadge(status: job.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.xs),
                    border: Border.all(color: AppColors.success),
                  ),
                  child: Text(
                    job.salaryMonthly != null ? '₹${job.salaryMonthly}/month' : 'Salary not set',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: job.salaryMonthly != null ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    if (job.area != null && job.area!.isNotEmpty) job.area,
                    job.languages.map((l) => Language.displayNames[l] ?? l).join(', '),
                  ].join(' • '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Posted: ${_formatDate(DateTime.parse(job.postedAt))}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(job.description, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
          TextButton(onPressed: onViewApplications, child: const Text('Applicants')),
          if (onRemind != null) TextButton(onPressed: onRemind, child: const Text('Remind')),
          if (onClose != null) TextButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}

class _MandatoryField {
  final GlobalKey key;
  final bool isValid;
  final FocusNode? focusNode;

  const _MandatoryField(this.key, this.isValid, {this.focusNode});
}

/// Handles both posting a new job and editing an existing one. Pass [job] +
/// [careReceiver] to open pre-filled in edit mode (same dialog doubles as
/// the "view full details" surface, since every field is visible); leave
/// both null to post a brand new job.
class _JobFormDialog extends ConsumerStatefulWidget {
  final JobModel? job;
  final CareReceiverModel? careReceiver;

  const _JobFormDialog({this.job, this.careReceiver});

  @override
  ConsumerState<_JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends ConsumerState<_JobFormDialog> {
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _medicalInfoController = TextEditingController();
  final _medicalConditionOtherController = TextEditingController();
  final _toiletAssistanceOtherController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _salaryController = TextEditingController();

  // Only mandatory text fields need a FocusNode — that's what lets Post
  // literally put the cursor in the first one that's missing.
  final _areaFocusNode = FocusNode();
  final _ageFocusNode = FocusNode();
  final _weightFocusNode = FocusNode();
  final _salaryFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();

  // One key per mandatory field, in the order they appear on the form, so
  // Post can scroll to whichever one is first still-invalid.
  final _cityKey = GlobalKey();
  final _areaKey = GlobalKey();
  final _ageKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _weightKey = GlobalKey();
  final _medicalConditionsKey = GlobalKey();
  final _vitalMonitoringTypesKey = GlobalKey();
  final _salaryKey = GlobalKey();
  final _dutyTypeKey = GlobalKey();
  final _frequencyKey = GlobalKey();
  final _languagesKey = GlobalKey();
  final _descriptionKey = GlobalKey();

  // Only turns true once Post has been pressed with something missing —
  // before that, fields don't show red just because they're empty.
  bool _showValidationErrors = false;

  // Job Location
  String? _city;

  // About Patient
  String? _gender;
  String? _mobility;
  String? _communication;
  String? _feedingType;
  List<String> _medicalAssistance = [];
  bool _hasMedicalCondition = false;
  List<String> _medicalConditions = [];
  List<String> _toiletAssistance = [];
  bool _requiresVitalMonitoring = false;
  List<String> _vitalMonitoringTypes = [];

  // Duty
  String? _dutyType;
  String? _frequencyOfCare;
  DateTime? _startDate;

  List<String> _languages = [];
  String? _preferredGender; // null = no preference
  String? _preferredReligion; // null = no preference

  bool _submitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.job != null;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    final cr = widget.careReceiver;
    if (job != null && cr != null) {
      _city = job.city;
      _areaController.text = job.area ?? '';
      _descriptionController.text = job.description;
      _dutyType = job.dutyType;
      _frequencyOfCare = job.frequencyOfCare;
      _startDate = job.startDate == null ? null : DateTime.tryParse(job.startDate!);
      _languages = List.of(job.languages);
      _salaryController.text = job.salaryMonthly?.toString() ?? '';
      _preferredGender = job.preferredGender;
      _preferredReligion = job.preferredReligion;

      _ageController.text = cr.age.toString();
      _gender = cr.gender;
      _weightController.text = cr.weightKg.toString();
      _mobility = cr.mobility;
      _communication = cr.communication;
      _feedingType = cr.feedingType;
      _medicalAssistance = List.of(cr.medicalAssistance);
      _hasMedicalCondition = cr.hasMedicalCondition;
      _medicalConditions = List.of(cr.medicalConditions);
      _medicalInfoController.text = cr.medicalInfo ?? '';
      _medicalConditionOtherController.text = cr.medicalConditionOther ?? '';
      _toiletAssistance = List.of(cr.toiletAssistance);
      _toiletAssistanceOtherController.text = cr.toiletAssistanceOther ?? '';
      _requiresVitalMonitoring = cr.requiresVitalMonitoring;
      _vitalMonitoringTypes = List.of(cr.vitalMonitoringTypes);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _areaController.dispose();
    _medicalInfoController.dispose();
    _medicalConditionOtherController.dispose();
    _toiletAssistanceOtherController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _salaryController.dispose();
    _areaFocusNode.dispose();
    _ageFocusNode.dispose();
    _weightFocusNode.dispose();
    _salaryFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  int? get _age => int.tryParse(_ageController.text.trim());
  int? get _weightKg => int.tryParse(_weightController.text.trim());
  int? get _salaryMonthly => int.tryParse(_salaryController.text.trim());

  bool get _isCityValid => _city != null;
  bool get _isAreaValid => _areaController.text.trim().isNotEmpty;
  bool get _isAgeValid => _age != null && _age! >= 1 && _age! <= 120;
  bool get _isGenderValid => _gender != null;
  bool get _isWeightValid => _weightKg != null && _weightKg! >= 1 && _weightKg! <= 300;
  bool get _isMedicalConditionsValid => !_hasMedicalCondition || _medicalConditions.isNotEmpty;
  bool get _isVitalMonitoringTypesValid => !_requiresVitalMonitoring || _vitalMonitoringTypes.isNotEmpty;
  bool get _isDutyTypeValid => _dutyType != null;
  bool get _isFrequencyValid => _frequencyOfCare != null;
  bool get _isLanguagesValid => _languages.isNotEmpty;
  bool get _isSalaryValid => _salaryMonthly != null && _salaryMonthly! >= 1 && _salaryMonthly! <= 1000000;
  bool get _isDescriptionValid => _descriptionController.text.trim().isNotEmpty;

  bool get _canSubmit =>
      !_submitting &&
      _isCityValid &&
      _isAreaValid &&
      _isAgeValid &&
      _isGenderValid &&
      _isWeightValid &&
      _isMedicalConditionsValid &&
      _isVitalMonitoringTypesValid &&
      _isDutyTypeValid &&
      _isFrequencyValid &&
      _isLanguagesValid &&
      _isSalaryValid &&
      _isDescriptionValid;

  /// In on-form order, so the first invalid one found here is genuinely
  /// the first one the admin sees when Post scrolls them to it.
  List<_MandatoryField> get _mandatoryFieldsInOrder => [
        _MandatoryField(_cityKey, _isCityValid),
        _MandatoryField(_areaKey, _isAreaValid, focusNode: _areaFocusNode),
        _MandatoryField(_ageKey, _isAgeValid, focusNode: _ageFocusNode),
        _MandatoryField(_genderKey, _isGenderValid),
        _MandatoryField(_weightKey, _isWeightValid, focusNode: _weightFocusNode),
        _MandatoryField(_medicalConditionsKey, _isMedicalConditionsValid),
        _MandatoryField(_vitalMonitoringTypesKey, _isVitalMonitoringTypesValid),
        _MandatoryField(_salaryKey, _isSalaryValid, focusNode: _salaryFocusNode),
        _MandatoryField(_dutyTypeKey, _isDutyTypeValid),
        _MandatoryField(_frequencyKey, _isFrequencyValid),
        _MandatoryField(_languagesKey, _isLanguagesValid),
        _MandatoryField(_descriptionKey, _isDescriptionValid, focusNode: _descriptionFocusNode),
      ];

  /// Post is always clickable — this is what runs when it's tapped. With
  /// something missing, it flags every missing mandatory field red and
  /// jumps straight to the first one instead of submitting.
  Future<void> _handlePostPressed() async {
    if (_submitting) return;
    if (!_canSubmit) {
      setState(() => _showValidationErrors = true);
      _MandatoryField? firstInvalid;
      for (final field in _mandatoryFieldsInOrder) {
        if (!field.isValid) {
          firstInvalid = field;
          break;
        }
      }
      if (firstInvalid != null) {
        final target = firstInvalid;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = target.key.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
          target.focusNode?.requestFocus();
        });
      }
      return;
    }
    await _submit();
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final careReceiver = CareReceiverInput(
        age: _age!,
        gender: _gender!,
        weightKg: _weightKg!,
        mobility: _mobility,
        communication: _communication,
        feedingType: _feedingType,
        medicalAssistance: _medicalAssistance,
        hasMedicalCondition: _hasMedicalCondition,
        medicalConditions: _hasMedicalCondition ? _medicalConditions : null,
        medicalInfo:
            _medicalInfoController.text.trim().isEmpty ? null : _medicalInfoController.text.trim(),
        medicalConditionOther: _medicalConditions.contains(MedicalCondition.other) &&
                _medicalConditionOtherController.text.trim().isNotEmpty
            ? _medicalConditionOtherController.text.trim()
            : null,
        toiletAssistance: _toiletAssistance,
        toiletAssistanceOther: _toiletAssistance.contains(ToiletAssistance.others) &&
                _toiletAssistanceOtherController.text.trim().isNotEmpty
            ? _toiletAssistanceOtherController.text.trim()
            : null,
        requiresVitalMonitoring: _requiresVitalMonitoring,
        vitalMonitoringTypes: _requiresVitalMonitoring ? _vitalMonitoringTypes : null,
      );
      final startDate = _startDate == null
          ? null
          : '${_startDate!.year.toString().padLeft(4, '0')}-'
              '${_startDate!.month.toString().padLeft(2, '0')}-'
              '${_startDate!.day.toString().padLeft(2, '0')}';

      if (_isEditing) {
        await ref.read(adminJobsRepositoryProvider).update(
              widget.job!.id,
              careReceiver: careReceiver,
              city: _city!,
              area: _areaController.text.trim(),
              description: _descriptionController.text.trim(),
              dutyType: _dutyType!,
              frequencyOfCare: _frequencyOfCare!,
              startDate: startDate,
              languages: _languages,
              salaryMonthly: _salaryMonthly!,
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
            );
      } else {
        await ref.read(adminJobsRepositoryProvider).create(
              careReceiver: careReceiver,
              city: _city!,
              area: _areaController.text.trim(),
              description: _descriptionController.text.trim(),
              dutyType: _dutyType!,
              frequencyOfCare: _frequencyOfCare!,
              startDate: startDate,
              languages: _languages,
              salaryMonthly: _salaryMonthly!,
              preferredGender: _preferredGender,
              preferredReligion: _preferredReligion,
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Job #${widget.job!.jobNumber}' : 'Post New Job'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Job Location', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _cityKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _city,
                  decoration: InputDecoration(
                    labelText: 'City (Mandatory)',
                    errorText: _showValidationErrors && !_isCityValid ? 'Please select a city' : null,
                  ),
                  items: City.all
                      .map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c)))
                      .toList(),
                  onChanged: (value) => setState(() => _city = value),
                ),
              ),
              if (_city != null) ...[
                const SizedBox(height: AppSpacing.sm),
                KeyedSubtree(
                  key: _areaKey,
                  child: TextField(
                    controller: _areaController,
                    focusNode: _areaFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Area in ${City.displayNames[_city] ?? _city} (Mandatory)',
                      errorText: _showValidationErrors && !_isAreaValid ? 'Area is required' : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('About Patient', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _ageKey,
                child: TextField(
                  controller: _ageController,
                  focusNode: _ageFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Patient's Age (Mandatory)",
                    errorText: _showValidationErrors && !_isAgeValid ? 'Age is required (1-120)' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _genderKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _gender,
                  decoration: InputDecoration(
                    labelText: "Patient's Gender (Mandatory)",
                    errorText: _showValidationErrors && !_isGenderValid ? 'Please select a gender' : null,
                  ),
                  items: const [
                    DropdownMenuItem(value: Gender.male, child: Text('Male')),
                    DropdownMenuItem(value: Gender.female, child: Text('Female')),
                    DropdownMenuItem(value: Gender.other, child: Text('Other')),
                  ],
                  onChanged: (value) => setState(() => _gender = value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _weightKey,
                child: TextField(
                  controller: _weightController,
                  focusNode: _weightFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Patient's Weight (kg) (Mandatory)",
                    errorText:
                        _showValidationErrors && !_isWeightValid ? 'Weight is required (1-300 kg)' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _mobility,
                decoration: const InputDecoration(labelText: 'Mobility'),
                items: Mobility.all
                    .map((m) => DropdownMenuItem(value: m, child: Text(Mobility.displayNames[m] ?? m)))
                    .toList(),
                onChanged: (value) => setState(() => _mobility = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _communication,
                decoration: const InputDecoration(labelText: 'Communication'),
                items: Communication.all
                    .map((c) => DropdownMenuItem(value: c, child: Text(Communication.displayNames[c] ?? c)))
                    .toList(),
                onChanged: (value) => setState(() => _communication = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _feedingType,
                decoration: const InputDecoration(labelText: 'Feeding'),
                items: FeedingType.all
                    .map((f) => DropdownMenuItem(value: f, child: Text(FeedingType.displayNames[f] ?? f)))
                    .toList(),
                onChanged: (value) => setState(() => _feedingType = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Medicine', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              VitaMultiSelectChips(
                options: MedicalAssistance.all,
                labels: MedicalAssistance.displayNames,
                selected: _medicalAssistance,
                onChanged: (next) => setState(() => _medicalAssistance = next),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Has a medical condition the caregiver should know about?'),
                value: _hasMedicalCondition,
                onChanged: (value) => setState(() {
                  _hasMedicalCondition = value;
                  if (!value) _medicalConditions = [];
                }),
              ),
              if (_hasMedicalCondition) ...[
                KeyedSubtree(
                  key: _medicalConditionsKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Condition(s) (Mandatory)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _showValidationErrors && !_isMedicalConditionsValid ? AppColors.error : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      VitaMultiSelectChips(
                        options: MedicalCondition.all,
                        labels: MedicalCondition.displayNames,
                        selected: _medicalConditions,
                        onChanged: (next) => setState(() => _medicalConditions = next),
                      ),
                      if (_showValidationErrors && !_isMedicalConditionsValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Select at least one condition',
                            style: TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      if (_medicalConditions.contains(MedicalCondition.other)) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: _medicalConditionOtherController,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Please describe the other condition'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _medicalInfoController,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Important information for the caregiver'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text('Toilet Assistance', style: TextStyle(fontWeight: FontWeight.w600)),
              const Text(
                'What assistance is required? Select all that apply.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.xs),
              VitaMultiSelectChips(
                options: ToiletAssistance.all,
                labels: ToiletAssistance.displayNames,
                selected: _toiletAssistance,
                onChanged: (next) => setState(() => _toiletAssistance = next),
              ),
              if (_toiletAssistance.contains(ToiletAssistance.others)) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _toiletAssistanceOtherController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Please describe the other toilet assistance'),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Is regular vital monitoring required?'),
                value: _requiresVitalMonitoring,
                onChanged: (value) => setState(() {
                  _requiresVitalMonitoring = value;
                  if (!value) _vitalMonitoringTypes = [];
                }),
              ),
              if (_requiresVitalMonitoring) ...[
                KeyedSubtree(
                  key: _vitalMonitoringTypesKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select what needs monitoring (Mandatory)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              _showValidationErrors && !_isVitalMonitoringTypesValid ? AppColors.error : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      VitaMultiSelectChips(
                        options: VitalMonitoringType.all,
                        labels: VitalMonitoringType.displayNames,
                        selected: _vitalMonitoringTypes,
                        onChanged: (next) => setState(() => _vitalMonitoringTypes = next),
                      ),
                      if (_showValidationErrors && !_isVitalMonitoringTypesValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Select at least one vital to monitor',
                            style: TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('About Nurse/Caregiver Requirement', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _salaryKey,
                child: TextField(
                  controller: _salaryController,
                  focusNode: _salaryFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Salary (₹/month) (Mandatory)',
                    errorText: _showValidationErrors && !_isSalaryValid ? 'Salary is required' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _dutyTypeKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _dutyType,
                  decoration: InputDecoration(
                    labelText: 'Hours Care Needed (Mandatory)',
                    errorText: _showValidationErrors && !_isDutyTypeValid ? 'Please select duty hours' : null,
                  ),
                  items: DutyType.all
                      .map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d)))
                      .toList(),
                  onChanged: (value) => setState(() => _dutyType = value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _frequencyKey,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _frequencyOfCare,
                  decoration: InputDecoration(
                    labelText: 'Frequency of Care (Mandatory)',
                    errorText: _showValidationErrors && !_isFrequencyValid ? 'Please select a frequency' : null,
                  ),
                  items: FrequencyOfCare.all
                      .map((f) => DropdownMenuItem(value: f, child: Text(FrequencyOfCare.displayNames[f] ?? f)))
                      .toList(),
                  onChanged: (value) => setState(() => _frequencyOfCare = value),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // A persistent heading, unlike the old design where the button's
              // own label doubled as the display text — that meant "Preferred
              // Start Date" disappeared the moment a date was picked, leaving
              // just a bare date with no context for what it was.
              const Text('Preferred Start Date', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                onPressed: _pickStartDate,
                child: Text(
                  _startDate == null
                      ? 'Select date'
                      : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              KeyedSubtree(
                key: _languagesKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Language Preference (Mandatory)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _showValidationErrors && !_isLanguagesValid ? AppColors.error : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    VitaMultiSelectChips(
                      options: Language.all,
                      labels: Language.displayNames,
                      selected: _languages,
                      onChanged: (next) => setState(() => _languages = next),
                    ),
                    if (_showValidationErrors && !_isLanguagesValid)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Select at least one language',
                          style: TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _preferredGender,
                decoration: const InputDecoration(labelText: 'Preferred Caregiver Gender'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('No preference')),
                  DropdownMenuItem<String?>(value: Gender.male, child: Text('Male')),
                  DropdownMenuItem<String?>(value: Gender.female, child: Text('Female')),
                ],
                onChanged: (value) => setState(() => _preferredGender = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _preferredReligion,
                decoration: const InputDecoration(labelText: 'Preferred Caregiver Religion'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No preference')),
                  // "Others" is excluded — a valid caregiver's own religion
                  // at registration, but not offered as a job preference.
                  ...Religion.all.where((r) => r != Religion.others).map(
                        (r) => DropdownMenuItem<String?>(value: r, child: Text(Religion.displayNames[r] ?? r)),
                      ),
                ],
                onChanged: (value) => setState(() => _preferredReligion = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              KeyedSubtree(
                key: _descriptionKey,
                child: TextField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocusNode,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'More details you want to share about patient or requirement which can '
                        'help caregiver to decide (Mandatory)',
                    border: const OutlineInputBorder(),
                    errorText: _showValidationErrors && !_isDescriptionValid ? 'Please add a description' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          // Always clickable — missing fields are handled inside
          // _handlePostPressed (highlight + scroll), not by disabling this.
          onPressed: _submitting ? null : _handlePostPressed,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEditing ? 'Save Changes' : 'Post'),
        ),
      ],
    );
  }
}

