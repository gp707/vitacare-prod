import 'package:vitacare_shared/vitacare_shared.dart';

/// Accurate, status-specific copy for every non-funnel verification status —
/// avoids showing a generic "under review" message once the caregiver is
/// actually verified, rejected, or assigned. Used at the top of
/// ProfileViewScreen (the caregiver's default post-funnel landing screen).
String statusMessageFor(String status, String? rejectionMessage) {
  switch (status) {
    case VerificationStatus.available:
      // Deliberately action-oriented, not passive — a caregiver is
      // expected to actively browse and apply (Find Jobs tab), not just
      // wait to be notified; there's no "job match" push, only the daily
      // 8am status-confirmation reminder (see CLAUDE.md).
      return "You're verified and available. Head to Find Jobs to browse openings and apply.";
    case VerificationStatus.unavailable:
      return "You're verified, but currently marked as not taking work. Contact the office to change this.";
    case VerificationStatus.assigned:
      return "You're currently assigned to a job.";
    case VerificationStatus.rejected:
      return rejectionMessage == null || rejectionMessage.isEmpty
          ? 'Your application was not approved. Contact the office for details.'
          : 'Your application was not approved: $rejectionMessage';
    default:
      return "Your profile is under review. We'll notify you once verified.";
  }
}
