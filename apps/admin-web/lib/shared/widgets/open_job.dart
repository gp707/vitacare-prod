import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../features/jobs/widgets/job_detail_dialog.dart';
import '../../features/organisation_requirements/widgets/requirement_widgets.dart';

/// Opens a job — or an organisation requirement — in place, in the same detail view the Jobs screen
/// and the Audit Logs use. Shared by every screen that links to a job (Accepted, Caregivers…).
/// A requirement's Edit button closes the view and goes to the Jobs screen, where editing lives.
Future<void> openJobOrRequirement(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required bool isRequirement,
}) async {
  if (jobId.isEmpty) return;
  if (!isRequirement) {
    await showDialog<void>(context: context, builder: (_) => JobDetailDialog(jobId: jobId));
    return;
  }
  try {
    final (requirement, _) = await ref.read(adminOrganisationRequirementsRepositoryProvider).getDetail(jobId);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => RequirementReadOnlyDialog(
        requirement: requirement,
        onEdit: () {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pushNamed('/jobs');
        },
      ),
    );
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
