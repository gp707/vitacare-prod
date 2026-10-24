import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import '../../analytics/analytics.dart';
import '../core/providers.dart';

import '../core/connectivity/connectivity_banner.dart';
import '../core/navigation/navigator_key.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';
import 'package:nursenow_app/caregiver/app/app.dart' show CaregiverSessionWatcher;
import 'package:nursenow_app/caregiver/core/providers.dart' as caregiver;
import 'pinch_to_zoom_wrapper.dart';
import 'router.dart';

/// Redirects to /login the moment the session becomes unauthenticated,
/// from anywhere in the app — not just while SplashScreen happens to be
/// mounted (which is only true briefly at cold launch). This is what
/// makes a token invalidated mid-session (e.g. an admin blocking the
/// account, or ApiClient's own error interceptor reacting to AUTH_004/
/// AUTH_005 on some unrelated call) actually kick the user out immediately,
/// regardless of which screen they're currently on. Lives above the
/// Navigator (in MaterialApp.builder), so it uses navigatorKey rather than
/// Navigator.of(context) — this context has no Navigator ancestor of its
/// own. SplashScreen keeps its own separate SessionAuthenticated handling
/// (deep-link restoration) — that's a one-time, cold-launch-only concern
/// this widget deliberately doesn't touch.
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

/// Which part of the app a route belongs to, for usage analytics. Caregiver
/// routes are namespaced (`/caregiver/...`); the host's own shared routes
/// (`/profile`) belong to the individual or organisation flow depending on
/// who is logged in.
String analyticsFlowForRoute(String name, {String? role}) {
  if (name.startsWith('/caregiver')) return Analytics.caregiverFlow;
  if (name == '/' || name == '/login' || name == '/register') return 'auth';
  if (name.startsWith('/org-')) return 'organisation';
  if (role == 'organisation') return 'organisation';
  if (role == 'individual') return 'individual';
  return 'auth';
}

String _flowForRoute(String name) {
  String? role;
  final context = navigatorKey.currentContext;
  if (context != null) {
    final session = ProviderScope.containerOf(context, listen: false).read(sessionProvider);
    if (session is SessionAuthenticated) role = session.role;
  }
  return analyticsFlowForRoute(name, role: role);
}

/// Starts usage analytics once, wiring each flow's own API client (so an
/// event is attributed to whichever session — individual/organisation or
/// caregiver — it came from). Renders nothing itself.
class AnalyticsBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const AnalyticsBootstrap({super.key, required this.child});

  @override
  ConsumerState<AnalyticsBootstrap> createState() => _AnalyticsBootstrapState();
}

class _AnalyticsBootstrapState extends ConsumerState<AnalyticsBootstrap> {
  @override
  void initState() {
    super.initState();
    Analytics.initWithDio(
      hostDio: ref.read(apiClientProvider).dio,
      caregiverDio: ref.read(caregiver.apiClientProvider).dio,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class NurseNowApp extends StatelessWidget {
  static final _analyticsObserver = AnalyticsNavigatorObserver(flowFor: _flowForRoute);

  /// The route the browser's URL/hash actually pointed at when the page
  /// loaded (captured in main() before runApp) — threaded down to
  /// SplashScreen so a web page refresh can restore the page the account
  /// was actually on instead of always landing on their home tab.
  final String? initialDeepLinkRoute;

  const NurseNowApp({super.key, this.initialDeepLinkRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JustHeal',
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
      navigatorObservers: [_analyticsObserver],
      initialRoute: '/',
      routes: buildRoutes(initialDeepLinkRoute: initialDeepLinkRoute),
      // Both session watchers are independent — each only listens to its
      // own flow's sessionProvider (this app's own Individual/Organisation
      // session vs. the ported caregiver flow's own session) and redirects
      // only when its own flow logs out, never the other's.
      builder: (context, child) => AnalyticsBootstrap(
        child: SessionWatcher(
          child: CaregiverSessionWatcher(
            child: ConnectivityBanner(child: PinchToZoomWrapper(child: child!)),
          ),
        ),
      ),
    );
  }
}
