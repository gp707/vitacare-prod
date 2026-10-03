import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nursenow_app/patient_hospital/core/navigation/navigator_key.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';

/// NOTE: the old `CaregiverApp` (its own `MaterialApp`) is gone — this
/// flow is merged into the host JustHeal app's single `MaterialApp`/
/// `Navigator` (see apps/justheal-app/lib/patient_hospital/app/app.dart), not a second one.
/// `buildCaregiverRoutes()` (router.dart) is merged straight into the
/// host's own flat route table instead.
///
/// Watches the caregiver session for a mid-session invalidation (the auth
/// interceptor's onUnauthorized callback triggers SessionNotifier.logout(),
/// which flips state to SessionUnauthenticated) and redirects to JustHeal's
/// own unified `/login` the moment it happens — otherwise a caregiver whose
/// token expired while the app was already open would just keep seeing
/// silently-failing requests on whatever screen they were on. Deliberately
/// `/login`, not `/caregiver/login` (the ported NurseJobs-only screen) —
/// a caregiver logging out should land back on the one shared JustHeal
/// login screen, same as everyone else, not a separate "NurseJobs" screen
/// that no longer has any normal way in. Named distinctly from the host's
/// own `SessionWatcher` (same file name, `app/app.dart`, in the host)
/// since both now live in the same program — each watches its own
/// independent `sessionProvider` and only reacts to its own flow's logout,
/// never the other's.
class CaregiverSessionWatcher extends ConsumerWidget {
  final Widget child;

  const CaregiverSessionWatcher({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionUnauthenticated) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
    return child;
  }
}
