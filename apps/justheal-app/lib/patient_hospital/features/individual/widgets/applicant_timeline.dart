import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// "14 Nov 2026, 6:32 PM".
String _formatDateTime(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final meridiem = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day} ${months[date.month - 1]} ${date.year}, $hour12:${date.minute.toString().padLeft(2, '0')} $meridiem';
}

/// The candidate's full action history on this application — every
/// transition with who did it and exactly when, newest first (the current
/// status is the one worth seeing without scrolling). `decidedByName`, when
/// present, names exactly who accepted/rejected — the patient/family
/// themselves, or an admin who intervened on their behalf via admin-web —
/// rather than a vague "you"/"the employer". A caregiver-initiated close
/// or self-withdrawal (`decidedBy == null`) is always the caregiver's own
/// doing, so those lines never need a name.
class ApplicantTimeline extends StatefulWidget {
  final JobApplicationModel application;

  const ApplicantTimeline(this.application, {super.key});

  @override
  State<ApplicantTimeline> createState() => _ApplicantTimelineState();
}

class _ApplicantTimelineState extends State<ApplicantTimeline> {
  static const _fontSize = AppTypography.small;

  // Collapsed by default — each applicant tile's log is independent state,
  // one instance of this widget per candidate, so expanding one never
  // affects any other candidate's own tile.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final entries = <MapEntry<DateTime, String>>[];
    if (application.appliedAt != null) {
      final at = DateTime.parse(application.appliedAt!).toLocal();
      entries.add(MapEntry(at, 'Applied: ${_formatDateTime(at)}'));
    }
    if (application.acceptedAt != null) {
      final at = DateTime.parse(application.acceptedAt!).toLocal();
      final by = application.decidedByName != null
          ? ' by ${application.decidedByName}'
          : '';
      entries.add(MapEntry(at, 'Accepted$by: ${_formatDateTime(at)}'));
    }
    // Shown whenever completedAt is set, regardless of the application's
    // CURRENT status — e.g. still shown as history after the candidate is
    // later accepted again ("Accept Anyway") or re-applies, neither of
    // which clear completedAt any more (see
    // OrganisationRequirementApplicationsRepository.upsert/decide).
    if (application.completedAt != null) {
      final at = DateTime.parse(application.completedAt!).toLocal();
      var text = 'Closed by Caregiver: ${_formatDateTime(at)}';
      if (application.closeReason != null) {
        text = '$text\nReason: ${CaregiverCloseReason.displayNames[application.closeReason] ?? application.closeReason}';
      }
      entries.add(MapEntry(at, text));
    }
    // Shown whenever rejectedAt is set, regardless of the application's
    // CURRENT status — same reasoning as completedAt above, so a
    // previously-declined-then-accepted-anyway (or re-applied) candidate's
    // rejection stays visible as history instead of silently vanishing.
    if (application.rejectedAt != null) {
      final at = DateTime.parse(application.rejectedAt!).toLocal();
      final label = application.decidedByName != null
          ? 'Rejected by ${application.decidedByName}'
          : 'Rejected by Caregiver';
      var text = '$label: ${_formatDateTime(at)}';
      if (application.declineReason != null &&
          application.declineReason!.isNotEmpty) {
        text = '$text\nReason: ${application.declineReason!}';
      }
      entries.add(MapEntry(at, text));
    }
    // A candidate can re-apply, then be decided on again — shown last since
    // it always comes after whatever prior outcome it followed.
    if (application.reappliedAt != null) {
      final at = DateTime.parse(application.reappliedAt!).toLocal();
      entries.add(MapEntry(at, 'Re-applied: ${_formatDateTime(at)}'));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    // Newest first — the current status is the one worth seeing without
    // having to scroll for it, same convention as caregiver-app's own
    // ApplicationTimeline.
    entries.sort((a, b) => b.key.compareTo(a.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                _expanded ? 'Hide Activity Log' : 'Show Activity Log',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: _fontSize,
                  decoration: TextDecoration.underline,
                ),
              ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 2),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                entry.value,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: _fontSize),
              ),
            ),
        ],
      ],
    );
  }
}
