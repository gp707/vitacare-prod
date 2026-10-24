import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/state/session_notifier.dart';
import 'package:nursenow_app/analytics/analytics.dart';

/// Shared by every authenticated screen's VitaAppBarTitle onTripleTap — the
/// Individual/Organisation Profile screen already has its own local
/// _logout doing the exact same two steps (reused there directly instead
/// of this, since it was already present); every other screen reaches for
/// this helper so the hidden triple-tap-the-logo gesture (see
/// VitaAppBarTitle's own doc comment — this replaced a visible Logout
/// button on request) works identically everywhere without duplicating
/// the logout+navigate sequence at each call site.
Future<void> logoutAndNavigateToLogin(BuildContext context, WidgetRef ref) async {
  Analytics.tapHere('logout');
  final navigator = Navigator.of(context);
  await ref.read(sessionProvider.notifier).logout();
  navigator.pushNamedAndRemoveUntil('/login', (route) => false);
}
