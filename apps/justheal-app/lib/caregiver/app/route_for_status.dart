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

/// Route arguments for `/caregiver/my-jobs` — lets a caller land directly
/// on a specific tab instead of always defaulting to Applied (tab 0).
class MyAssignmentScreenArgs {
  final int initialTabIndex;
  const MyAssignmentScreenArgs({this.initialTabIndex = 0});
}

/// Paired with [routeForStatus] — pass as `arguments:` on the same
/// `pushNamed`/`pushNamedAndRemoveUntil` call. "default them to MyJobs"
/// means the right TAB too, not just the right screen: a caregiver who
/// just became `assigned` lands straight on the Selected tab, not Applied.
/// Every other status has nothing to say here (`routes:` ignores a null
/// `settings.arguments`).
Object? routeArgumentsForStatus(SessionAuthenticated session) {
  if (session.verificationStatus == VerificationStatus.assigned) {
    return const MyAssignmentScreenArgs(initialTabIndex: 1);
  }
  return null;
}
