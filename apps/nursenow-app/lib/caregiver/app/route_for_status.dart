import 'package:vitacare_shared/vitacare_shared.dart';
import '../features/auth/state/session_state.dart';

/// Maps verification_status to a route, per SPEC.md section 12.2. Every
/// field (including what used to be "Advanced Details") is collected at
/// registration, so pending_call is the only funnel status left — it lands
/// on the waiting screen. assigned (currently working a job) lands
/// straight on MyJobs, so the caregiver sees the job they're on without an
/// extra tap. rejected lands on Jobs — browsing what's available doubles
/// as a nudge to go fix/resubmit their profile. available/unavailable go
/// straight to Profile View (shows status + full profile, no separate
/// click) as before.
String routeForStatus(SessionAuthenticated session) {
  switch (session.verificationStatus) {
    case VerificationStatus.pendingCall:
      return '/caregiver/pending-call';
    case VerificationStatus.assigned:
      return '/caregiver/my-jobs';
    case VerificationStatus.rejected:
      return '/caregiver/jobs';
    default:
      return '/caregiver/profile';
  }
}
