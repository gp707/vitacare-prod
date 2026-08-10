import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/app_shell.dart';

/// SPEC.md 6.6 — admin posts a job, it's broadcast to all caregivers via
/// push, and caregivers respond accept/reject/more_details. This screen
/// covers post/list/close/view-responses; caregiver-facing browsing lives
/// in apps/caregiver-app's Jobs tab.
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

  Future<void> _viewResponses(JobModel job) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _JobResponsesDialog(job: job),
    );
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
                        onViewResponses: () => _viewResponses(job),
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
  final VoidCallback onViewResponses;

  const _JobRow({
    required this.job,
    required this.onClose,
    required this.onRemind,
    required this.onViewResponses,
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
                        WorkType.displayNames[job.workType] ?? job.workType,
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
                  '${City.displayNames[job.city] ?? job.city} • '
                  '${ServiceMode.displayNames[job.dutyTimings] ?? job.dutyTimings} • '
                  '${Language.displayNames[job.language] ?? job.language}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(job.description, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(onPressed: onViewResponses, child: const Text('Responses')),
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
  String? _workType;
  String? _city;
  String? _dutyTimings;
  String? _language;
  String? _genderNeeded;
  String? _religion;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _workType != null &&
      _city != null &&
      _dutyTimings != null &&
      _language != null &&
      _genderNeeded != null &&
      _religion != null &&
      _descriptionController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(adminJobsRepositoryProvider).create(
            workType: _workType!,
            city: _city!,
            description: _descriptionController.text.trim(),
            dutyTimings: _dutyTimings!,
            language: _language!,
            genderNeeded: _genderNeeded!,
            religion: _religion!,
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
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _workType,
                decoration: const InputDecoration(labelText: 'Work Type'),
                items: WorkType.all
                    .map((w) => DropdownMenuItem(value: w, child: Text(WorkType.displayNames[w] ?? w)))
                    .toList(),
                onChanged: (value) => setState(() => _workType = value),
              ),
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
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _dutyTimings,
                decoration: const InputDecoration(labelText: 'Duty Timings'),
                items: ServiceMode.all
                    .map((s) => DropdownMenuItem(value: s, child: Text(ServiceMode.displayNames[s] ?? s)))
                    .toList(),
                onChanged: (value) => setState(() => _dutyTimings = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: Language.all
                    .map((l) => DropdownMenuItem(value: l, child: Text(Language.displayNames[l] ?? l)))
                    .toList(),
                onChanged: (value) => setState(() => _language = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _genderNeeded,
                decoration: const InputDecoration(labelText: 'Gender Needed'),
                items: const [
                  DropdownMenuItem(value: Gender.male, child: Text('Male')),
                  DropdownMenuItem(value: Gender.female, child: Text('Female')),
                ],
                onChanged: (value) => setState(() => _genderNeeded = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _religion,
                decoration: const InputDecoration(labelText: 'Religion'),
                items: Religion.all
                    .map((r) => DropdownMenuItem(value: r, child: Text(Religion.displayNames[r] ?? r)))
                    .toList(),
                onChanged: (value) => setState(() => _religion = value),
              ),
              const SizedBox(height: AppSpacing.sm),
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

class _JobResponsesDialog extends ConsumerStatefulWidget {
  final JobModel job;

  const _JobResponsesDialog({required this.job});

  @override
  ConsumerState<_JobResponsesDialog> createState() => _JobResponsesDialogState();
}

class _JobResponsesDialogState extends ConsumerState<_JobResponsesDialog> {
  List<JobResponseModel>? _responses;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (_, responses) = await ref.read(adminJobsRepositoryProvider).getDetail(widget.job.id);
      if (mounted) setState(() => _responses = responses);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Responses — ${WorkType.displayNames[widget.job.workType] ?? widget.job.workType}'),
      content: SizedBox(
        width: 420,
        child: _errorMessage != null
            ? Text(_errorMessage!, style: const TextStyle(color: AppColors.error))
            : _responses == null
                ? const Center(child: VitaLoadingIndicator())
                : _responses!.isEmpty
                    ? const Text('No responses yet.', style: TextStyle(color: AppColors.textSecondary))
                    : SizedBox(
                        height: 300,
                        child: ListView.separated(
                          itemCount: _responses!.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final r = _responses![index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${r.fullName} — ${r.response}'),
                              subtitle: Text(
                                [r.phone, if (r.message != null && r.message!.isNotEmpty) r.message]
                                    .join(' • '),
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
