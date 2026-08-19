import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Salary's unit follows Frequency of Care — same convention as the Jobs
/// list row and the Post/Edit form.
String _salaryUnit(String? frequencyOfCare) => frequencyOfCare == FrequencyOfCare.daily ? 'day' : 'month';

/// Read-only detail view opened by tapping a job row — every field as
/// plain text (About Patient / About Nurse-Caregiver Requirement, same
/// grouping as the Post/Edit form and caregiver-app's job card), with an
/// Edit button handing off to the existing _JobFormDialog edit flow.
class JobReadOnlyDetailDialog extends StatelessWidget {
  final JobModel job;
  final VoidCallback onEdit;

  const JobReadOnlyDetailDialog({super.key, required this.job, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final careReceiver = job.careReceiver;
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Job #${job.jobNumber}'),
          const SizedBox(width: AppSpacing.sm),
          _StatusChip(status: job.status),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job.postedByRole == UserRole.individual)
                _DetailRow(
                  'Posted by',
                  'Patient/family${job.postedByName != null ? ' — ${job.postedByName}' : ''}',
                ),
              _DetailRow('Job Location', [
                City.displayNames[job.city] ?? job.city,
                if (job.area != null && job.area!.isNotEmpty) job.area!,
              ].join(', ')),
              _DetailRow('Hours Care Needed', DutyType.displayNames[job.dutyType] ?? job.dutyType),
              _DetailRow(
                'Frequency of Care',
                job.frequencyOfCare != null
                    ? FrequencyOfCare.displayNames[job.frequencyOfCare] ?? job.frequencyOfCare!
                    : 'Not set',
              ),
              _DetailRow(
                'Salary',
                job.salaryAmount != null ? '₹${job.salaryAmount}/${_salaryUnit(job.frequencyOfCare)}' : 'Not set',
              ),
              if (job.startDate != null) _DetailRow('Preferred Start Date', job.startDate!),
              _DetailRow('Languages', job.languages.map((l) => Language.displayNames[l] ?? l).join(', ')),
              if (job.preferredGender != null)
                _DetailRow('Preferred Gender', Gender.displayNames[job.preferredGender] ?? job.preferredGender!),
              if (job.preferredReligion != null)
                _DetailRow('Preferred Religion', Religion.displayNames[job.preferredReligion] ?? job.preferredReligion!),
              if (job.description != null && job.description!.isNotEmpty)
                _DetailRow('More Details', job.description!),
              if (job.rejectionReason != null) _DetailRow('Rejection Reason', job.rejectionReason!),
              _DetailRow('Posted', _formatDate(DateTime.parse(job.postedAt))),
              if (careReceiver != null) ...[
                const Divider(height: AppSpacing.lg),
                const Text('About Patient', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                _DetailRow('Age', '${careReceiver.age} yrs'),
                _DetailRow('Gender', Gender.displayNames[careReceiver.gender] ?? careReceiver.gender),
                _DetailRow('Weight', '${careReceiver.weightKg} kg'),
                _DetailRow('Mobility', Mobility.displayNames[careReceiver.mobility] ?? careReceiver.mobility),
                _DetailRow(
                  'Communication',
                  Communication.displayNames[careReceiver.communication] ?? careReceiver.communication,
                ),
                _DetailRow('Feeding', FeedingType.displayNames[careReceiver.feedingType] ?? careReceiver.feedingType),
                _DetailRow(
                  'Medical Assistance',
                  careReceiver.medicalAssistance.map((m) => MedicalAssistance.displayNames[m] ?? m).join(', '),
                ),
                _DetailRow(
                  'Medical Condition',
                  careReceiver.hasMedicalCondition
                      ? careReceiver.medicalConditions.map((c) => MedicalCondition.displayNames[c] ?? c).join(', ')
                      : 'None',
                ),
                if (careReceiver.medicalConditionOther != null && careReceiver.medicalConditionOther!.isNotEmpty)
                  _DetailRow('Other Condition', careReceiver.medicalConditionOther!),
                _DetailRow(
                  'Toilet Assistance',
                  careReceiver.toiletAssistance.map((t) => ToiletAssistance.displayNames[t] ?? t).join(', '),
                ),
                if (careReceiver.toiletAssistanceOther != null && careReceiver.toiletAssistanceOther!.isNotEmpty)
                  _DetailRow('Other Toilet Assistance', careReceiver.toiletAssistanceOther!),
                _DetailRow(
                  'Vital Monitoring',
                  careReceiver.requiresVitalMonitoring
                      ? careReceiver.vitalMonitoringTypes
                          .map((v) => VitalMonitoringType.displayNames[v] ?? v)
                          .join(', ')
                      : 'Not required',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
