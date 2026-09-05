import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import '../core/connectivity/connectivity_banner.dart';
import '../core/navigation/navigator_key.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';
import 'router.dart';

class CaregiverApp extends StatelessWidget {
  /// The route the browser's URL/hash actually pointed at when the page
  /// loaded (captured in main() before runApp) — threaded down to
  /// SplashScreen so a web page refresh can restore the tab/page the
  /// caregiver was actually on instead of always landing on Profile.
  /// Always "/" on mobile (no browser URL), so a no-op there.
  final String? initialDeepLinkRoute;

  const CaregiverApp({super.key, this.initialDeepLinkRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NurseJobs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          error: AppColors.error,
        ),
        fontFamily: AppTypography.fontFamily,
      ),
      navigatorKey: navigatorKey,
      initialRoute: '/',
      routes: buildRoutes(initialDeepLinkRoute: initialDeepLinkRoute),
      builder: (context, child) => SessionWatcher(child: ConnectivityBanner(child: child!)),
    );
  }
}

/// Watches the session for a mid-session invalidation (the auth
/// interceptor's onUnauthorized callback triggers SessionNotifier.logout(),
/// which flips state to SessionUnauthenticated) and redirects to /login the
/// moment it happens — otherwise a caregiver whose token expired while the
/// app was already open would just keep seeing silently-failing requests
/// on whatever screen they were on.
class SessionWatcher extends ConsumerWidget {
  final Widget child;

  const SessionWatcher({super.key, required this.child});

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
