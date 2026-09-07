import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../data/audit_log_models.dart';
import '../../jobs/widgets/job_detail_dialog.dart';

/// Shared rendering for an audit log entry's job/requirement link, target
/// link, and reason line — used by AuditLogsScreen's own table/mobile card
/// AND by CaregiverDetailScreen/IndividualDetailScreen/
/// OrganisationDetailScreen's own scoped "Recent Activity" previews, so all
/// four surfaces resolve/render display ids and links identically instead
/// of each keeping its own drifted-apart copy.

/// Same convention as the shared jobDisplayId() helper — kept local since
/// AuditLogEntry only carries the two raw resolved numbers, not a full
/// JobModel. Only meaningful once entry.jobId is known non-null, at which
/// point exactly one of adminJobNumber/patientJobNumber is always set.
String auditJobDisplayId(AuditLogEntry entry) {
  if (entry.adminJobNumber != null) {
    return 'ADMIN-JOB-${entry.adminJobNumber}';
  }
  return 'PAT-JOB-${entry.patientJobNumber}';
}

/// Same convention as organisationJobDisplayId() from the shared package —
/// kept local since AuditLogEntry only carries the raw resolved number, not
/// a full OrganisationRequirementModel.
String auditRequirementDisplayId(AuditLogEntry entry) =>
    'ORG-JOB-${entry.requirementNumber}';

/// The target user's own display id (NUR-/PAT-/ORG-`<n>`) — null when
/// there's no target at all, or the target is an admin/super_admin (no
/// display-id convention for those; the raw name is enough).
String? auditTargetDisplayId(AuditLogEntry entry) {
  switch (entry.targetUserRole) {
    case 'caregiver':
      return caregiverDisplayId(entry.targetCaregiverNumber);
    case 'individual':
      return patientDisplayId(entry.targetPatientNumber);
    case 'organisation':
      return organisationDisplayId(entry.targetOrgNumber);
    default:
      return null;
  }
}

/// A patient's/organisation's own reason for rejecting a caregiver
/// application, or a caregiver's own reason for closing a job/requirement
/// they'd been accepted onto — whichever the entry actually carries, if
/// either. Never both at once (one action produces one or the other, never
/// both), so checking `reason` first is just a fixed, arbitrary order.
String? auditReason(AuditLogEntry entry) {
  final after = entry.afterValue;
  if (after == null) return null;
  final reason = after['reason'];
  if (reason is String && reason.isNotEmpty) return reason;
  final closeReason = after['close_reason'];
  if (closeReason is String && closeReason.isNotEmpty) return closeReason;
  return null;
}

void openAuditJobDialog(BuildContext context, String jobId) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => JobDetailDialog(jobId: jobId),
  );
}

/// Job entries are clickable (opens JobDetailDialog). Organisation-
/// requirement entries show the same "display id + raw selectable UUID"
/// shape but aren't clickable — there's no admin-web dialog that opens a
/// requirement's detail from outside its own list screen, unlike jobs'
/// JobDetailDialog which is already a standalone public widget.
Widget buildJobOrRequirementCell(BuildContext context, AuditLogEntry entry) {
  if (entry.jobId != null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => openAuditJobDialog(context, entry.jobId!),
          child: Text(auditJobDisplayId(entry)),
        ),
        // The raw UUID, selectable so it can be copied straight into a DB
        // query or support ticket — the display id alone isn't enough when
        // you need the exact id.
        SelectableText(entry.jobId!,
            style: const TextStyle(
                fontSize: AppTypography.caption, color: AppColors.textSecondary)),
      ],
    );
  }
  if (entry.requirementNumber != null && entry.requirementId != null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(auditRequirementDisplayId(entry),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        SelectableText(entry.requirementId!,
            style: const TextStyle(
                fontSize: AppTypography.caption, color: AppColors.textSecondary)),
      ],
    );
  }
  return const Text('-');
}

/// Navigates to the target's own detail screen, if it has one — caregiver
/// targets via their profile id (CaregiverDetailScreen is keyed by profile
/// id, not user id), individual/organisation targets via their user id.
/// Admin/super_admin targets (or no target at all) have no detail screen,
/// so there's nothing to navigate to.
void openAuditTargetDetail(BuildContext context, AuditLogEntry entry) {
  switch (entry.targetUserRole) {
    case 'caregiver':
      if (entry.targetCaregiverProfileId != null) {
        Navigator.of(context)
            .pushNamed('/caregiver-detail', arguments: entry.targetCaregiverProfileId);
      }
      break;
    case 'individual':
      if (entry.targetUserId != null) {
        Navigator.of(context).pushNamed('/individual-detail', arguments: entry.targetUserId);
      }
      break;
    case 'organisation':
      if (entry.targetUserId != null) {
        Navigator.of(context).pushNamed('/organisation-detail', arguments: entry.targetUserId);
      }
      break;
  }
}

/// Shows the target's own display id (NUR-/PAT-/ORG-`<n>`) above their
/// name when the target is a caregiver/individual/organisation — an
/// admin/super_admin target (or no target at all) just shows the name. The
/// whole cell is tappable straight through to that account's own detail
/// screen whenever one exists (every case above except admin/no-target).
Widget buildTargetCell(BuildContext context, AuditLogEntry entry) {
  final displayId = auditTargetDisplayId(entry);
  if (entry.targetUserName == null) return const Text('-');
  final isLinkable = entry.targetUserRole == 'caregiver' ||
      entry.targetUserRole == 'individual' ||
      entry.targetUserRole == 'organisation';
  final content = displayId == null
      ? Text(entry.targetUserName!)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(displayId, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(entry.targetUserName!,
                style: const TextStyle(
                    fontSize: AppTypography.small, color: AppColors.textSecondary)),
          ],
        );
  if (!isLinkable) return content;
  return InkWell(
    onTap: () => openAuditTargetDetail(context, entry),
    child: content,
  );
}

/// A single "Reason: ..." line, or null when the entry carries no reason —
/// callers simply skip rendering anything when this returns null.
Widget? buildAuditReasonLine(AuditLogEntry entry) {
  final reason = auditReason(entry);
  if (reason == null) return null;
  return Text('Reason: $reason',
      style: const TextStyle(fontSize: AppTypography.small, fontStyle: FontStyle.italic));
}
