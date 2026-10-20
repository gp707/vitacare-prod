import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/core/navigation/navigator_key.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';

/// NOTE: the old `CaregiverApp` (its own `MaterialApp`) is gone — this
/// flow is merged into the host JustHeal app's single `MaterialApp`/
/// `Navigator` (see apps/justheal-app/lib/patient_hospital/app/app.dart), not a second one.
/// `buildCaregiverRoutes()` (router.dart) is merged straight into the
/// host's own flat route table instead.
///
/// Watches the caregiver session for two things, both forcing navigation
/// from anywhere via the global [navigatorKey] rather than a local
/// Navigator, since this widget sits above every screen (caregiver and
/// host alike — it's mounted once near the app root):
///
/// 1. A mid-session invalidation (the auth interceptor's onUnauthorized
///    callback triggers SessionNotifier.logout(), which flips state to
///    SessionUnauthenticated) — redirected to JustHeal's own unified
///    `/login` the moment it happens, otherwise a caregiver whose token
///    expired while the app was already open would just keep seeing
///    silently-failing requests on whatever screen they were on.
///    Deliberately `/login`, not `/caregiver/login` (the ported
///    NurseJobs-only screen) — a caregiver logging out should land back on
///    the one shared JustHeal login screen, same as everyone else, not a
///    separate "NurseJobs" screen that no longer has any normal way in.
///
/// 2. Getting accepted onto a job (verification_status flipping to
///    `assigned`) while already using the app elsewhere — e.g. sitting on
///    Jobs or Profile when an admin accepts their application. On its own,
///    routeForStatus() already sends an `assigned` caregiver straight to
///    MyJobs at login — but that only resolves the NEXT time they log in.
///    This poll (same cheap single-GET refreshStatus()/cadence rationale
///    as PendingCallScreen's own poll, which still owns the pendingCall ->
///    anything-else transition — this only fires for available/unavailable
///    -> assigned, so the two never fight over the same redirect) is what
///    catches it live, so "default them to MyJobs when selected for a job"
///    holds true mid-session too, not just at next login.
///
/// Named distinctly from the host's own `SessionWatcher` (same file name,
/// `app/app.dart`, in the host) since both now live in the same program —
/// each watches its own independent `sessionProvider` and only reacts to
/// its own flow's events, never the other's.
class CaregiverSessionWatcher extends ConsumerStatefulWidget {
  final Widget child;

  const CaregiverSessionWatcher({super.key, required this.child});

  @override
  ConsumerState<CaregiverSessionWatcher> createState() => _CaregiverSessionWatcherState();
}

class _CaregiverSessionWatcherState extends ConsumerState<CaregiverSessionWatcher> {
  static const _pollInterval = Duration(seconds: 20);
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // A no-op (refreshStatus() returns false immediately) whenever there's
    // no authenticated caregiver session, so this costs nothing for the
    // host app's own (non-caregiver) users even though the watcher is
    // always mounted.
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      ref.read(sessionProvider.notifier).refreshStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionUnauthenticated) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
        return;
      }
      if (previous is SessionAuthenticated &&
          previous.verificationStatus != VerificationStatus.assigned &&
          previous.verificationStatus != VerificationStatus.pendingCall &&
          next is SessionAuthenticated &&
          next.verificationStatus == VerificationStatus.assigned) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/caregiver/my-jobs', (route) => false);
      }
    });
    return widget.child;
  }
}
