import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../app/update_required_screen.dart';
import '../../../app/maintenance_screen.dart';
import '../../../core/providers.dart';
import '../../../core/version/app_version_repository.dart';
import '../../../core/version/app_maintenance_repository.dart';
import 'package:nursenow_app/caregiver/app/route_for_status.dart' as caregiver_route;
import 'package:nursenow_app/caregiver/core/providers.dart' as caregiver;
import 'package:nursenow_app/caregiver/features/auth/state/session_notifier.dart' as caregiver_session;
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart' as caregiver_session_state;

/// Routes safe to restore on refresh once authenticated — every route
/// registered in router.dart's buildRoutes() map except the pre-auth ones
/// ('/', '/login', '/register'). All are argument-free. Kept in sync with
/// router.dart by hand, same convention as the other two apps' equivalent
/// sets. '/org-home'/'/org-post-requirement' are organisation-only —
/// restoring the wrong one for the resolved session's role is guarded
/// against separately below, not by this set (an individual account could
/// still have this route sitting stale in the URL from a previous
/// different-role session on a shared browser). There is no individual-only
/// equivalent any more — posting a requirement is now part of registration
/// itself (RegistrationScreen), not a separate post-auth route.
const _restorableRoutes = {
  '/home',
  '/profile',
  '/org-home',
  '/org-post-requirement',
};

class SplashScreen extends ConsumerStatefulWidget {
  final String? initialDeepLinkRoute;

  const SplashScreen({super.key, this.initialDeepLinkRoute});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  UpdateRequiredInfo? _updateInfo;
  MaintenanceInfo? _maintenanceInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthConfigThenLoadSession());
  }

  /// All three calls (maintenance/version check, OTP config) are
  /// unauthenticated and fail open, so they're safe to run in parallel —
  /// same convention as caregiver-app's own splash screen.
  Future<void> _checkAuthConfigThenLoadSession() async {
    final results = await Future.wait([
      ref.read(appMaintenanceRepositoryProvider).checkForMaintenance(),
      ref.read(appVersionRepositoryProvider).checkForUpdate(),
      ref.read(authConfigRepositoryProvider).isOtpEnabled(),
    ]);
    if (!mounted) return;

    final maintenanceInfo = results[0] as MaintenanceInfo?;
    final updateInfo = results[1] as UpdateRequiredInfo?;
    final otpEnabled = results[2] as bool;
    ref.read(otpModeProvider.notifier).state = otpEnabled;

    // Maintenance takes priority over a stale-build nag — if the app is
    // down entirely, telling the user to update first would be pointless.
    if (maintenanceInfo != null) {
      setState(() {
        _maintenanceInfo = maintenanceInfo;
        _updateInfo = null;
      });
      return;
    }
    if (updateInfo != null) {
      setState(() {
        _maintenanceInfo = null;
        _updateInfo = updateInfo;
      });
      return;
    }
    setState(() {
      _maintenanceInfo = null;
      _updateInfo = null;
    });
    ref.read(sessionProvider.notifier).loadSession();
  }

  /// Fallback for when the HOST's own session resolves to
  /// SessionUnauthenticated (no stored Individual/Organisation token) —
  /// before concluding "truly logged out" and sending the account to
  /// /login, also check whether a caregiver session is stored, since the
  /// caregiver flow has no cold-launch restore of its own (unlike this
  /// host flow, which already handles its own session right here). Without
  /// this, a caregiver whose app process got killed (swiped from recents,
  /// or the OS reclaiming memory) would always be forced to re-login on
  /// next open, even though caregiver tokens are deliberately non-expiring
  /// specifically because this app has no re-login flow built for them
  /// (see CLAUDE.md) — this was a real, reported bug, not just a gap.
  Future<void> _tryRestoreCaregiverSessionOrLogin() async {
    final caregiverLocalStorage = ref.read(caregiver.localStorageProvider);
    if (caregiverLocalStorage.accessToken == null) {
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return;
    }
    await ref.read(caregiver_session.sessionProvider.notifier).loadSession();
    if (!mounted) return;
    final caregiverSession = ref.read(caregiver_session.sessionProvider);
    if (caregiverSession is caregiver_session_state.SessionAuthenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        caregiver_route.routeForStatus(caregiverSession),
        (route) => false,
        arguments: caregiver_route.routeArgumentsForStatus(caregiverSession),
      );
    } else {
      // A stored caregiver token exists but came back invalid/expired
      // (SessionUnauthenticated — the token itself was rejected) or
      // SessionLoadError (e.g. no connectivity right now). Either way,
      // falling back to /login matches today's existing behavior for
      // every other case — not a regression, since this path is only
      // reached when the host session was already unauthenticated too.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_maintenanceInfo != null) {
      return MaintenanceScreen(message: _maintenanceInfo!.message, onRetry: _checkAuthConfigThenLoadSession);
    }
    if (_updateInfo != null) {
      return UpdateRequiredScreen(storeUrl: _updateInfo!.storeUrl, message: _updateInfo!.message);
    }

    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionUnauthenticated) {
        _tryRestoreCaregiverSessionOrLogin();
      } else if (next is SessionAuthenticated) {
        final restoreRoute = widget.initialDeepLinkRoute;
        final isOrgOnlyRoute = restoreRoute == '/org-home' || restoreRoute == '/org-post-requirement';
        final roleMismatch = isOrgOnlyRoute && !next.isOrganisation;
        final target = restoreRoute != null && _restorableRoutes.contains(restoreRoute) && !roleMismatch
            ? restoreRoute
            : next.homeRoute;
        Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
      }
    });

    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The new JustHeal lockup already bakes in the wordmark +
            // "Helping Hands, Healing Hearts" tagline, so this renders it
            // directly rather than through VitaSplashBranding (which would
            // duplicate that text as separate captions below the image —
            // right for admin-web's splash, which still uses the plain
            // icon+wordmark logo_lockup.webp, but not for this one).
            Image.asset('packages/vitacare_ui/assets/branding/justheal_splash_logo.webp', width: 200),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'By VitaCasaHealth',
              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (session is SessionLoadError) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  session.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () => ref.read(sessionProvider.notifier).loadSession(),
                child: const Text('Retry'),
              ),
            ] else
              const VitaLoadingIndicator(),
          ],
        ),
      ),
    );
  }
}
