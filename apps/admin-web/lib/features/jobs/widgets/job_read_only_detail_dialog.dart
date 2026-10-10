import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'scope_of_work_button.dart';
import '../../audit_logs/screens/audit_logs_screen.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// "{role} — {name} · {phone}", tolerating either name or phone being
/// absent — mirrors AdminJobsScreen's own _PosterLine text construction.
String _posterValueText({required String role, String? name, String? phone}) {
  final roleAndName = name != null ? '$role — $name' : role;
  return phone != null ? '$roleAndName · $phone' : roleAndName;
}

/// Salary's unit follows Frequency of Care — same convention as the Jobs
/// list row and the Post/Edit form.
String _salaryUnit(String? frequencyOfCare) =>
    frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month';

/// Read-only detail view opened by tapping a job row — every field as
/// plain text, grouped Patient Details / Care Preferences / Nurse Fee
/// Guidance in the exact same field set and order as `_JobFormDialog`
/// (see admin_jobs_screen.dart) — this is what admin actually reviews
/// before approving (via Edit) or rejecting a job, so it must show exactly
/// what the patient/admin submitted, nothing more. Vital Monitoring and the
/// free-text description are not shown here at all — admin's create/edit
/// form doesn't collect them, so surfacing them here (even as leftover data
/// on an older job) would suggest they're still part of the reviewable
/// shape. Communication has been removed from the product entirely, so
/// there's nothing left to show for it either way. Has its own Edit button
/// handing off to the existing _JobFormDialog edit flow.
class JobReadOnlyDetailDialog extends StatelessWidget {
  final JobModel job;
  final VoidCallback onEdit;

  const JobReadOnlyDetailDialog(
      {super.key, required this.job, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final careReceiver = job.careReceiver;
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(jobDisplayId(job)),
          const SizedBox(width: AppSpacing.sm),
          _StatusChip(status: job.status),
        ],
      ),
      content: SizedBox(
        width: context.dialogWidth(480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job.postedByRole != null)
                _DetailRow(
                  'Posted by',
                  _posterValueText(
                    role: job.postedByRole == UserRole.individual ? 'Patient/family' : 'Admin',
                    name: job.postedByName,
                    phone: job.postedByPhone,
                  ),
                  // Only a patient/family poster has a profile screen to
                  // open — there's no equivalent detail screen for an
                  // admin account.
                  onTap: job.postedByRole == UserRole.individual
                      ? () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pushNamed('/individual-detail', arguments: job.postedBy);
                        }
                      : null,
                ),
              if (job.rejectionReason != null)
                _DetailRow('Rejection Reason', job.rejectionReason!),
              _DetailRow('Posted', _formatDate(DateTime.parse(job.postedAt))),
              const Divider(height: AppSpacing.lg),
              const Text('Patient Details',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              if (careReceiver != null) ...[
                if (careReceiver.patientName != null && careReceiver.patientName!.isNotEmpty)
                  _DetailRow('Patient Name', careReceiver.patientName!),
                _DetailRow('Age', '${careReceiver.age} yrs'),
                _DetailRow(
                    'Gender',
                    Gender.displayNames[careReceiver.gender] ??
                        careReceiver.gender),
                _DetailRow('Weight', '${careReceiver.weightKg} kg'),
              ],
              _DetailRow('City', City.displayNames[job.city] ?? job.city),
              if (job.area != null && job.area!.isNotEmpty)
                _DetailRow('Area', job.area!),
              if (careReceiver != null) ...[
                _DetailRow(
                  'Medical Condition',
                  careReceiver.hasMedicalCondition
                      ? careReceiver.medicalConditions
                          .map((c) => MedicalCondition.displayNames[c] ?? c)
                          .join(', ')
                      : 'None',
                ),
                if (careReceiver.medicalConditionOther != null &&
                    careReceiver.medicalConditionOther!.isNotEmpty)
                  _DetailRow(
                      'Other Condition', careReceiver.medicalConditionOther!),
              ],
              const SizedBox(height: AppSpacing.md),
              const Text('Care Preferences',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              _DetailRow('Hours Care Needed',
                  DutyType.displayNames[job.dutyType] ?? job.dutyType),
              if (job.startDate != null)
                _DetailRow('Preferred Start Date', job.startDate!),
              // Only ever set on a NurseNow individual's own posting — null
              // for an admin-posted job.
              if (job.careDuration != null)
                _DetailRow('Duration Care is Needed', CareDuration.displayNames[job.careDuration] ?? job.careDuration!),
              if (careReceiver != null) ...[
                _DetailRow(
                  'Toilet Assistance',
                  careReceiver.toiletAssistance
                      .map((t) => ToiletAssistance.displayNames[t] ?? t)
                      .join(', '),
                ),
                if (careReceiver.toiletAssistanceOther != null &&
                    careReceiver.toiletAssistanceOther!.isNotEmpty)
                  _DetailRow('Other Toilet Assistance',
                      careReceiver.toiletAssistanceOther!),
                _DetailRow(
                    'Feeding/Medicine Assistance',
                    FeedingType.displayNames[careReceiver.feedingType] ??
                        careReceiver.feedingType),
              ],
              if (job.preferredGender != null)
                _DetailRow(
                    'Preferred Caregiver Gender',
                    Gender.displayNames[job.preferredGender] ??
                        job.preferredGender!),
              const SizedBox(height: AppSpacing.md),
              const Text('Nurse Fee Guidance',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              _DetailRow(
                'Frequency of Care',
                job.frequencyOfCare != null
                    ? FrequencyOfCare.displayNames[job.frequencyOfCare] ??
                        job.frequencyOfCare!
                    : 'Not set',
              ),
              _DetailRow(
                'Salary',
                job.salaryAmount != null
                    ? '₹${job.salaryAmount}/${_salaryUnit(job.frequencyOfCare)}'
                    : 'Not set',
              ),
              if (careReceiver != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 160,
                        child: Text('Scope of Work', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      ScopeOfWorkButton(careReceiver: careReceiver),
                    ],
                  ),
                ),
              ],
              const Divider(height: AppSpacing.lg),
              _JobNotesSection(job: job),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed(
              '/audit-logs',
              arguments: AuditLogsRouteArgs(jobId: job.id),
            );
          },
          child: const Text('View Activity Log'),
        ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
        ElevatedButton(onPressed: onEdit, child: const Text('Edit')),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      JobStatus.pendingReview => Colors.orange,
      JobStatus.active => AppColors.success,
      _ => AppColors.textSecondary,
    };
    final label = switch (status) {
      JobStatus.pendingReview => 'Pending Review',
      JobStatus.active => 'Active',
      JobStatus.closed => 'Closed',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: AppTypography.small, fontWeight: FontWeight.w600)),
    );
  }
}

/// Admin-only personal/internal note about this job — never shown to the
/// job poster or any caregiver-facing endpoint. Kept as its own small
/// stateful widget (rather than making the whole dialog stateful) since
/// this is the only part of the dialog with editable state.
class _JobNotesSection extends ConsumerStatefulWidget {
  final JobModel job;

  const _JobNotesSection({required this.job});

  @override
  ConsumerState<_JobNotesSection> createState() => _JobNotesSectionState();
}

class _JobNotesSectionState extends ConsumerState<_JobNotesSection> {
  bool _editing = false;
  bool _saving = false;
  late final _controller = TextEditingController(text: widget.job.notes ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(adminJobsRepositoryProvider)
          .upsertNotes(widget.job.id, _controller.text.trim());
      if (mounted) setState(() => _editing = false);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
            if (!_editing)
              TextButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_editing)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Internal notes about this job (never shown to the poster or caregivers)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Save'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _editing = false;
                              _controller.text = widget.job.notes ?? '';
                            }),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          )
        else
          Text(
            widget.job.notes?.isNotEmpty == true ? widget.job.notes! : 'No notes yet.',
            style: TextStyle(
              color: widget.job.notes?.isNotEmpty == true ? null : AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  /// When provided, [value] becomes a tappable, underlined link (e.g. to
  /// the poster's own profile screen) instead of plain text.
  final VoidCallback? onTap;

  const _DetailRow(this.label, this.value, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final valueText = Text(
      value,
      style: onTap != null
          ? const TextStyle(color: AppColors.primaryDark, decoration: TextDecoration.underline)
          : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: onTap != null ? InkWell(onTap: onTap, child: valueText) : valueText),
        ],
      ),
    );
  }
}
