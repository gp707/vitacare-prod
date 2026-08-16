import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';
import '../data/admin_jobs_repository.dart';

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
      builder: (dialogContext) => const _CreateJobDialog(),
    );
    if (created == true) await _load();
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
      builder: (dialogContext) => _JobApplicationsDialog(job: job),
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

class _JobRow extends StatelessWidget {
  final JobModel job;
  final VoidCallback? onClose;
  final VoidCallback? onRemind;
  final VoidCallback onViewApplications;

  const _JobRow({
    required this.job,
    required this.onClose,
    required this.onRemind,
    required this.onViewApplications,
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
                Text(
                  [
                    if (job.area != null && job.area!.isNotEmpty) job.area,
                    job.languages.map((l) => Language.displayNames[l] ?? l).join(', '),
                  ].join(' • '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(job.description, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(onPressed: onViewApplications, child: const Text('Applicants')),
          if (onRemind != null) TextButton(onPressed: onRemind, child: const Text('Remind')),
          if (onClose != null) TextButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}

class _CreateJobDialog extends ConsumerStatefulWidget {
  const _CreateJobDialog();

  @override
  ConsumerState<_CreateJobDialog> createState() => _CreateJobDialogState();
}

class _CreateJobDialogState extends ConsumerState<_CreateJobDialog> {
  final _descriptionController = TextEditingController();
  final _areaController = TextEditingController();
  final _medicalInfoController = TextEditingController();

  // Job Location
  String? _city;

  // Care Receiver
  String? _mobility;
  String? _communication;
  String? _feedingType;
  bool? _tubeFeedingNeedsAssistance;
  List<String> _medicalAssistance = [];
  bool _hasMedicalCondition = false;
  List<String> _medicalConditions = [];

  // Duty
  String? _dutyType;
  DateTime? _startDate;

  List<String> _languages = [];
  String? _preferredGender; // null = no preference
  String? _preferredReligion; // null = no preference

  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    _areaController.dispose();
    _medicalInfoController.dispose();
    super.dispose();
  }

  bool get _needsTubeFeedingAnswer =>
      _feedingType == FeedingType.tubeFeeding || _feedingType == FeedingType.oralAndTube;

  bool get _canSubmit =>
      !_submitting &&
      _city != null &&
      _mobility != null &&
      _communication != null &&
      _feedingType != null &&
      (!_needsTubeFeedingAnswer || _tubeFeedingNeedsAssistance != null) &&
      (!_hasMedicalCondition || _medicalConditions.isNotEmpty) &&
      _dutyType != null &&
      _languages.isNotEmpty &&
      _descriptionController.text.trim().isNotEmpty;

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
      await ref.read(adminJobsRepositoryProvider).create(
            careReceiver: CareReceiverInput(
              mobility: _mobility!,
              communication: _communication!,
              feedingType: _feedingType!,
              tubeFeedingNeedsAssistance: _needsTubeFeedingAnswer ? _tubeFeedingNeedsAssistance : null,
              medicalAssistance: _medicalAssistance,
              hasMedicalCondition: _hasMedicalCondition,
              medicalConditions: _hasMedicalCondition ? _medicalConditions : null,
              medicalInfo: _medicalInfoController.text.trim().isEmpty
                  ? null
                  : _medicalInfoController.text.trim(),
            ),
            city: _city!,
            area: _areaController.text.trim(),
            description: _descriptionController.text.trim(),
            dutyType: _dutyType!,
            startDate: _startDate == null
                ? null
                : '${_startDate!.year.toString().padLeft(4, '0')}-'
                    '${_startDate!.month.toString().padLeft(2, '0')}-'
                    '${_startDate!.day.toString().padLeft(2, '0')}',
            languages: _languages,
            preferredGender: _preferredGender,
            preferredReligion: _preferredReligion,
          );
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
      title: const Text('Post New Job'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Job Location', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _city,
                decoration: const InputDecoration(labelText: 'City'),
                items: City.all
                    .map((c) => DropdownMenuItem(value: c, child: Text(City.displayNames[c] ?? c)))
                    .toList(),
                onChanged: (value) => setState(() => _city = value),
              ),
              if (_city != null) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _areaController,
                  decoration: InputDecoration(labelText: 'Area in ${City.displayNames[_city] ?? _city}'),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('Care Receiver', style: TextStyle(fontWeight: FontWeight.bold)),
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
                onChanged: (value) => setState(() {
                  _feedingType = value;
                  _tubeFeedingNeedsAssistance = null;
                }),
              ),
              if (_needsTubeFeedingAnswer)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Needs caregiver assistance with tube feeding'),
                  value: _tubeFeedingNeedsAssistance ?? false,
                  onChanged: (value) => setState(() => _tubeFeedingNeedsAssistance = value),
                ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Medical Assistance Required', style: TextStyle(fontWeight: FontWeight.w600)),
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
                const Text('Condition(s)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.xs),
                VitaMultiSelectChips(
                  options: MedicalCondition.all,
                  labels: MedicalCondition.displayNames,
                  selected: _medicalConditions,
                  onChanged: (next) => setState(() => _medicalConditions = next),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _medicalInfoController,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Important information for the caregiver'),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              const Text('Duty', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _dutyType,
                decoration: const InputDecoration(labelText: 'Duty Type'),
                items: DutyType.all
                    .map((d) => DropdownMenuItem(value: d, child: Text(DutyType.displayNames[d] ?? d)))
                    .toList(),
                onChanged: (value) => setState(() => _dutyType = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _pickStartDate,
                child: Text(
                  _startDate == null
                      ? 'Start Date'
                      : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Language Preference', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpacing.xs),
              VitaMultiSelectChips(
                options: Language.all,
                labels: Language.displayNames,
                selected: _languages,
                onChanged: (next) => setState(() => _languages = next),
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
                  ...Religion.all.map(
                    (r) => DropdownMenuItem<String?>(value: r, child: Text(Religion.displayNames[r] ?? r)),
                  ),
                ],
                onChanged: (value) => setState(() => _preferredReligion = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
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
          onPressed: _canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Post'),
        ),
      ],
    );
  }
}

class _JobApplicationsDialog extends ConsumerStatefulWidget {
  final JobModel job;

  const _JobApplicationsDialog({required this.job});

  @override
  ConsumerState<_JobApplicationsDialog> createState() => _JobApplicationsDialogState();
}

class _JobApplicationsDialogState extends ConsumerState<_JobApplicationsDialog> {
  List<JobApplicationModel>? _applications;
  String? _errorMessage;
  String? _decidingApplicationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (_, applications) = await ref.read(adminJobsRepositoryProvider).getDetail(widget.job.id);
      if (mounted) setState(() => _applications = applications);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _decide(JobApplicationModel application, String status) async {
    setState(() => _decidingApplicationId = application.id);
    try {
      await ref
          .read(adminJobsRepositoryProvider)
          .decideApplication(widget.job.id, application.id, status);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _decidingApplicationId = null);
    }
  }

  void _viewProfile(JobApplicationModel application) {
    Navigator.of(context).pushNamed('/caregiver-detail', arguments: application.profileId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Applicants — ${DutyType.displayNames[widget.job.dutyType] ?? widget.job.dutyType} in '
        '${City.displayNames[widget.job.city] ?? widget.job.city}',
      ),
      content: SizedBox(
        width: 480,
        child: _errorMessage != null
            ? Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
            : _applications == null
                ? const Center(child: VitaLoadingIndicator())
                : _applications!.isEmpty
                    ? const Text('No applicants yet.', style: TextStyle(color: AppColors.textSecondary))
                    : SizedBox(
                        height: 340,
                        child: ListView.separated(
                          itemCount: _applications!.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final application = _applications![index];
                            final isDeciding = _decidingApplicationId == application.id;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${application.fullName} — ${application.status}'),
                              subtitle: Text(application.phone),
                              trailing: isDeciding
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: VitaLoadingIndicator(size: 20),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: () => _viewProfile(application),
                                          child: const Text('Profile'),
                                        ),
                                        if (application.status == JobApplicationStatus.applied) ...[
                                          TextButton(
                                            onPressed: () =>
                                                _decide(application, JobApplicationStatus.accepted),
                                            child: const Text('Accept'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _decide(application, JobApplicationStatus.rejected),
                                            style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                            child: const Text('Reject'),
                                          ),
                                        ] else if (application.status == JobApplicationStatus.accepted)
                                          TextButton(
                                            onPressed: () =>
                                                _decide(application, JobApplicationStatus.rejected),
                                            style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                            child: const Text('Reject'),
                                          ),
                                      ],
                                    ),
                            );
                          },
                        ),
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
