import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../data/admin_organisation_requirements_repository.dart';

/// "{role} — {name} · {phone}", tolerating either name or phone being
/// absent — mirrors admin_jobs_screen.dart's own _PosterLine/
/// job_read_only_detail_dialog.dart's _posterValueText construction.
String _posterValueText({required String role, String? name, String? phone}) {
  final roleAndName = name != null ? '$role — $name' : role;
  return phone != null ? '$roleAndName · $phone' : roleAndName;
}

/// Row/dialog widgets for an organisation requirement, extracted out of the
/// former standalone AdminOrganisationRequirementsScreen so AdminJobsScreen
/// can render organisation requirements merged into its single Jobs list.
/// Kept as a distinct set of widgets (not unified with _JobRow/_JobFormDialog
/// in admin_jobs_screen.dart) since organisation_requirements is a wholly
/// separate table/model from jobs (see "NurseNow" in CLAUDE.md) — only the
/// browse/list view is merged, not the underlying create/edit shapes.
class RequirementRow extends StatelessWidget {
  final AdminOrganisationRequirement requirement;
  final VoidCallback onTap;
  /// Only supplied for a pending_review requirement — approves it. Admin
  /// owns no fields on an active/closed requirement, so there is nothing
  /// left to edit once it's live; the row shows no Approve/Edit action then.
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback onViewApplicants;

  const RequirementRow({
    super.key,
    required this.requirement,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
    required this.onViewApplicants,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(requirementDisplayId(requirement),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  RequirementStatusBadge(status: requirement.status),
                ],
              ),
              const SizedBox(height: 2),
              Text(requirement.organisationName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              InkWell(
                onTap: () => Navigator.of(context)
                    .pushNamed('/organisation-detail', arguments: requirement.postedBy),
                child: Text(
                  _posterValueText(
                    role: 'Posted by',
                    name: requirement.contactPersonName,
                    phone: requirement.organisationPhone,
                  ),
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: AppTypography.small,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              if (requirement.rejectionReason != null)
                Text('Reason: ${requirement.rejectionReason}',
                    style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  Text(TypeOfNurse.displayNames[requirement.typeOfNurse] ??
                      requirement.typeOfNurse),
                  if (requirement.durationType != null)
                    Text(
                      '· ${RequirementDuration.displayNames[requirement.durationType] ?? requirement.durationType}',
                    ),
                  Text(
                      '· ${requirement.accommodationProvided ? 'Accommodation' : 'No accommodation'}'),
                  Text('· ${requirement.foodProvided ? 'Food' : 'No food'}'),
                  Text('· Vacancies: ${requirement.numberOfVacancies}'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                children: [
                  TextButton(
                      onPressed: onViewApplicants,
                      child: const Text('Applicants')),
                  if (onApprove != null)
                    TextButton(
                        onPressed: onApprove, child: const Text('Approve')),
                  if (onReject != null)
                    TextButton(
                        onPressed: onReject, child: const Text('Reject')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RequirementStatusBadge extends StatelessWidget {
  final String status;

  const RequirementStatusBadge({super.key, required this.status});

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

/// Admin approval is a bare click — the organisation set every field on
/// this requirement itself (see "NurseNow" in CLAUDE.md: "admin approval is
/// just click a button, approve/reject"). Only ever shown for a
/// pending_review requirement; there is nothing left for admin to edit once
/// it's active, since admin owns no fields on it at all.
class ApproveRequirementDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final Future<void> Function() onSubmit;

  const ApproveRequirementDialog(
      {super.key, required this.requirement, required this.onSubmit});

  @override
  State<ApproveRequirementDialog> createState() =>
      _ApproveRequirementDialogState();
}

class _ApproveRequirementDialogState extends State<ApproveRequirementDialog> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    await widget.onSubmit();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Approve ${requirementDisplayId(widget.requirement)}'),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: const Text(
          'This makes the requirement visible to caregivers. The organisation '
          'already set every field themselves — there is nothing for you to '
          'fill in.',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16, width: 16, child: VitaLoadingIndicator(size: 16))
              : const Text('Approve'),
        ),
      ],
    );
  }
}

class RequirementApplicantsDialog extends StatefulWidget {
  final AdminOrganisationRequirement requirement;
  final List<OrganisationRequirementApplicationModel> applications;
  final Future<void> Function(String applicationId, String status) onDecide;

  const RequirementApplicantsDialog({
    super.key,
    required this.requirement,
    required this.applications,
    required this.onDecide,
  });

  @override
  State<RequirementApplicantsDialog> createState() =>
      _RequirementApplicantsDialogState();
}

class _RequirementApplicantsDialogState
    extends State<RequirementApplicantsDialog> {
  String? _decidingId;

  Future<void> _decide(String applicationId, String status) async {
    setState(() => _decidingId = applicationId);
    await widget.onDecide(applicationId, status);
    if (mounted) Navigator.of(context).pop();
  }

  void _viewProfile(OrganisationRequirementApplicationModel application) {
    Navigator.of(context)
        .pushNamed('/caregiver-detail', arguments: application.profileId);
  }

  int get _acceptedCount =>
      widget.applications.where((a) => a.status == JobApplicationStatus.accepted).length;

  @override
  Widget build(BuildContext context) {
    final vacancies = widget.requirement.numberOfVacancies;
    return AlertDialog(
      title: Text(
        'Applicants — ${requirementDisplayId(widget.requirement)} '
        '($_acceptedCount / $vacancies vacanc${vacancies == 1 ? 'y' : 'ies'} filled)',
      ),
      content: SizedBox(
        width: context.dialogWidth(400),
        child: widget.applications.isEmpty
            ? const Text('No applicants yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final application in widget.applications)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(application.fullName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(application.phone),
                              ],
                            ),
                          ),
                          if (_decidingId == application.id)
                            const SizedBox(
                                height: 20,
                                width: 20,
                                child: VitaLoadingIndicator(size: 20))
                          else ...[
                            TextButton(
                              onPressed: () => _viewProfile(application),
                              child: const Text('Profile'),
                            ),
                            if (application.status ==
                                JobApplicationStatus.applied) ...[
                              TextButton(
                                onPressed: () => _decide(application.id,
                                    JobApplicationStatus.accepted),
                                child: const Text('Accept'),
                              ),
                              TextButton(
                                onPressed: () => _decide(application.id,
                                    JobApplicationStatus.rejected),
                                child: const Text('Reject'),
                              ),
                            ] else
                              Text(application.status),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }
}

/// Same wording as the shared organisationJobDisplayId() helper — kept as
/// a local copy since AdminOrganisationRequirement is admin-web's own
/// model (not the shared OrganisationRequirementModel that helper expects).
String requirementDisplayId(AdminOrganisationRequirement requirement) =>
    'ORG-JOB-${requirement.requirementNumber}';

/// Read-only detail view opened by tapping a requirement row — every field
/// as plain text, with an Approve button (pending_review only) handing off
/// to ApproveRequirementDialog.
class RequirementReadOnlyDialog extends StatelessWidget {
  final AdminOrganisationRequirement requirement;
  final VoidCallback? onApprove;

  const RequirementReadOnlyDialog(
      {super.key, required this.requirement, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(requirementDisplayId(requirement)),
          const SizedBox(width: AppSpacing.sm),
          RequirementStatusBadge(status: requirement.status),
        ],
      ),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('Organisation', requirement.organisationName ?? '—'),
              _DetailRow(
                'Contact Person',
                requirement.organisationPhone != null
                    ? '${requirement.contactPersonName ?? '—'} · ${requirement.organisationPhone}'
                    : requirement.contactPersonName ?? '—',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/organisation-detail', arguments: requirement.postedBy);
                },
              ),
              _DetailRow(
                'Type',
                OrganisationType.displayNames[requirement.organisationType] ??
                    requirement.organisationType ??
                    '—',
              ),
              _DetailRow(
                'Location',
                [
                  if (requirement.city != null)
                    City.displayNames[requirement.city] ?? requirement.city!,
                  if (requirement.area != null && requirement.area!.isNotEmpty)
                    requirement.area!,
                ].join(', '),
              ),
              const Divider(height: AppSpacing.lg),
              _DetailRow(
                  'Type of Nurse',
                  requirement.typeOfNurse == TypeOfNurse.others && requirement.typeOfNurseOther != null
                      ? '${TypeOfNurse.displayNames[requirement.typeOfNurse]}: ${requirement.typeOfNurseOther}'
                      : TypeOfNurse.displayNames[requirement.typeOfNurse] ?? requirement.typeOfNurse),
              _DetailRow('Number of Vacancies', requirement.numberOfVacancies.toString()),
              _DetailRow(
                'Preferred Caregiver Gender',
                requirement.preferredGender != null
                    ? Gender.displayNames[requirement.preferredGender] ?? requirement.preferredGender!
                    : 'No preference',
              ),
              _DetailRow(
                'Duration',
                requirement.durationType != null
                    ? RequirementDuration.displayNames[requirement.durationType] ??
                        requirement.durationType!
                    : '—',
              ),
              _DetailRow(
                  'Accommodation',
                  requirement.accommodationProvided
                      ? 'Provided'
                      : 'Not provided'),
              _DetailRow('Food',
                  requirement.foodProvided ? 'Provided' : 'Not provided'),
              if (requirement.specialSkills != null &&
                  requirement.specialSkills!.isNotEmpty)
                _DetailRow('Special Skills', requirement.specialSkills!),
              if (requirement.rejectionReason != null)
                _DetailRow('Rejection Reason', requirement.rejectionReason!),
              const Divider(height: AppSpacing.lg),
              _DetailRow('Posted', requirement.postedAt.split('T').first),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
        if (onApprove != null)
          ElevatedButton(onPressed: onApprove, child: const Text('Approve')),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  /// When provided, [value] becomes a tappable, underlined link (e.g. to
  /// the organisation's own profile screen) instead of plain text.
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
            width: 140,
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(child: onTap != null ? InkWell(onTap: onTap, child: valueText) : valueText),
        ],
      ),
    );
  }
}
