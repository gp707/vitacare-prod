import 'package:vitacare_shared/vitacare_shared.dart';
import '../features/auth/state/session_state.dart';

/// Maps verification_status to a route, per SPEC.md section 12.2. Every
/// field (including what used to be "Advanced Details") is collected at
/// registration, so pending_call is the only funnel status left — it lands
/// on the waiting screen; everything else goes straight to Profile View
/// (shows status + full profile, no separate click).
String routeForStatus(SessionAuthenticated session) {
  switch (session.verificationStatus) {
    case VerificationStatus.pendingCall:
      return '/pending-call';
    default:
      return '/profile';
  }
}
