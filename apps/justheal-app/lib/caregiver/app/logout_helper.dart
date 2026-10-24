import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/state/session_notifier.dart';
import 'package:nursenow_app/analytics/analytics.dart';

/// Mirrors lib/patient_hospital/app/logout_helper.dart exactly (own copy,
/// same duplication precedent as RateCardButton/WhatsAppHelpButton) —
/// shared by every authenticated caregiver screen's VitaAppBarTitle
/// onTripleTap except the Profile screen, which already has its own local
/// _logout doing the exact same two steps. JustHeal's own unified login,
/// not the ported NurseJobs-only screen — see CaregiverSessionWatcher in
/// app/app.dart for the same fix on the mid-session-invalidation path.
Future<void> logoutAndNavigateToLogin(BuildContext context, WidgetRef ref) async {
  Analytics.tapHere('logout');
  final navigator = Navigator.of(context);
  await ref.read(sessionProvider.notifier).logout();
  navigator.pushNamedAndRemoveUntil('/login', (route) => false);
}
