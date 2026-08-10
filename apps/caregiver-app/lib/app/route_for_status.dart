import 'package:vitacare_shared/vitacare_shared.dart';
import '../features/auth/state/session_state.dart';

/// Maps verification_status to a route, per SPEC.md section 12.2. Only the
/// onboarding-funnel routes are implemented in this phase (pending_call and
/// call_verified) — every later status lands directly on the caregiver's
/// own Profile View (shows status + full profile, no separate click) until
/// the dedicated Rejection Details / Home screens are built in a later phase.
String routeForStatus(SessionAuthenticated session) {
  switch (session.verificationStatus) {
    case VerificationStatus.pendingCall:
      return '/pending-call';
    case VerificationStatus.callVerified:
      return '/advanced-details';
    default:
      return '/profile';
  }
}
