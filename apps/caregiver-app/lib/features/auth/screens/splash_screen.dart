import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../app/route_for_status.dart';
import '../../../app/update_required_screen.dart';
import '../../../core/providers.dart';
import '../../../core/version/app_version_repository.dart';

/// Routes safe to restore on refresh once authenticated — every route
/// registered in router.dart's buildRoutes() map except the pre-auth ones
/// ('/', '/login', '/register'). All are argument-free, and bottom-nav
/// tabs (Jobs/MyJobs/Profile) are reachable regardless of
/// verification_status per CLAUDE.md, so restoring e.g. "/jobs" is valid
/// even for a pending_call caregiver. Kept in sync with router.dart by
/// hand, same convention as admin-web's equivalent set.
const _restorableRoutes = {'/pending-call', '/profile', '/profile/edit', '/jobs', '/my-jobs'};

class SplashScreen extends ConsumerStatefulWidget {
  final String? initialDeepLinkRoute;

  const SplashScreen({super.key, this.initialDeepLinkRoute});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  UpdateRequiredInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVersionThenLoadSession());
  }

  Future<void> _checkVersionThenLoadSession() async {
    // Both calls are unauthenticated and fail open, so they're safe to run
    // in parallel rather than sequentially.
    final results = await Future.wait([
      ref.read(appVersionRepositoryProvider).checkForUpdate(),
      ref.read(authConfigRepositoryProvider).isOtpEnabled(),
    ]);
    if (!mounted) return;

    final updateInfo = results[0] as UpdateRequiredInfo?;
    final otpEnabled = results[1] as bool;
    ref.read(otpModeProvider.notifier).state = otpEnabled;

    if (updateInfo != null) {
      setState(() => _updateInfo = updateInfo);
      return;
    }
    ref.read(sessionProvider.notifier).loadSession();
  }

  @override
  Widget build(BuildContext context) {
    if (_updateInfo != null) {
      return UpdateRequiredScreen(storeUrl: _updateInfo!.storeUrl, message: _updateInfo!.message);
    }

    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionUnauthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      } else if (next is SessionAuthenticated) {
        final restoreRoute = widget.initialDeepLinkRoute;
        final target = restoreRoute != null && _restorableRoutes.contains(restoreRoute)
            ? restoreRoute
            : routeForStatus(next);
        Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
      }
    });

    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VitaSplashBranding(appLabel: 'NURSEJOBS'),
            SizedBox(height: AppSpacing.xl),
            VitaLoadingIndicator(),
          ],
        ),
      ),
    );
  }
}
