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

/// Routes safe to restore on refresh once authenticated — every route
/// registered in router.dart's buildRoutes() map except the pre-auth ones
/// ('/', '/login', '/register'). All are argument-free. Kept in sync with
/// router.dart by hand, same convention as the other two apps' equivalent
/// sets. '/org-home'/'/org-post-requirement' are organisation-only and
/// '/post-requirement' is individual-only — restoring the wrong one for
/// the resolved session's role is guarded against separately below, not by
/// this set (an individual account could still have this route sitting
/// stale in the URL from a previous different-role session on a shared
/// browser).
const _restorableRoutes = {
  '/home',
  '/profile',
  '/post-requirement',
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
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      } else if (next is SessionAuthenticated) {
        final restoreRoute = widget.initialDeepLinkRoute;
        final isOrgOnlyRoute = restoreRoute == '/org-home' || restoreRoute == '/org-post-requirement';
        final isIndividualOnlyRoute = restoreRoute == '/post-requirement';
        final roleMismatch =
            (isOrgOnlyRoute && !next.isOrganisation) || (isIndividualOnlyRoute && next.isOrganisation);
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
            const VitaSplashBranding(appLabel: 'NURSENOW'),
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
