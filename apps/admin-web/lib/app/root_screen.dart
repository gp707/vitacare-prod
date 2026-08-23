import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';

/// Routes safe to restore on refresh once authenticated — every route
/// registered in router.dart's static buildRoutes() map (all argument-free
/// WidgetBuilders) plus '/caregivers' and '/jobs', both dynamic
/// (onGenerateRoute) but taking only a nullable argument
/// (initialStatus / initialFilter), so restoring either with no argument
/// behaves identically to visiting it fresh. Deliberately
/// excludes routes that require a non-null argument we have no way to
/// recover from a bare URL alone (/caregiver-detail, /audit-logs,
/// /individual-detail, /organisation-detail all take a required id) —
/// those fall back to the default /dashboard below, same as before this
/// restore behavior existed. Kept in sync with router.dart by hand, same
/// convention as other small duplicated route-name constants in this app.
const _restorableRoutes = {
  '/dashboard',
  '/admins',
  '/jobs',
  '/app-versions',
  '/patients-family',
  '/rehab-hospitals',
  '/caregivers',
  '/reports',
};

/// Checks for a stored session and redirects to /login, or back to
/// whatever page the admin was on before a refresh (falling back to
/// /dashboard if that page isn't safely restorable — see
/// _restorableRoutes). SPEC.md's admin screen list (13.1) doesn't name a
/// distinct splash screen, but this bootstrap step is still needed.
class RootScreen extends ConsumerStatefulWidget {
  final String? initialDeepLinkRoute;

  const RootScreen({super.key, this.initialDeepLinkRoute});

  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionProvider.notifier).loadSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AdminSessionState>(sessionProvider, (previous, next) {
      if (next is AdminSessionUnauthenticated) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      } else if (next is AdminSessionAuthenticated) {
        final restoreRoute = widget.initialDeepLinkRoute;
        final target =
            restoreRoute != null && _restorableRoutes.contains(restoreRoute)
                ? restoreRoute
                : '/dashboard';
        Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
      }
    });

    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: VitaLoadingIndicator()),
    );
  }
}
