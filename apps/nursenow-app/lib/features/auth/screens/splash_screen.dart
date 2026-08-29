import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../core/providers.dart';

/// Routes safe to restore on refresh once authenticated — every route
/// registered in router.dart's buildRoutes() map except the pre-auth ones
/// ('/', '/login', '/register'). All are argument-free. Kept in sync with
/// router.dart by hand, same convention as the other two apps' equivalent
/// sets. '/org-home'/'/org-post-requirement' are organisation-only and
/// '/post-requirement' is individual-only — restoring the wrong one for
/// the resolved session's role is guarded against separately below, not
/// by this set (an individual account could still have this route sitting
/// stale in the URL from a previous different-role session on a shared
/// browser).
const _restorableRoutes = {'/home', '/profile', '/post-requirement', '/org-home', '/org-post-requirement'};

class SplashScreen extends ConsumerStatefulWidget {
  final String? initialDeepLinkRoute;

  const SplashScreen({super.key, this.initialDeepLinkRoute});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthConfigThenLoadSession());
  }

  /// Unlike caregiver-app, nursenow-app has no existing pre-check to
  /// extend (no app-version-check here) — this is new wiring, not an
  /// extension. Unauthenticated and fails open to false (PIN mode), same
  /// contract as AuthConfigRepository.isOtpEnabled itself.
  Future<void> _checkAuthConfigThenLoadSession() async {
    final otpEnabled = await ref.read(authConfigRepositoryProvider).isOtpEnabled();
    if (!mounted) return;
    ref.read(otpModeProvider.notifier).state = otpEnabled;
    ref.read(sessionProvider.notifier).loadSession();
  }

  @override
  Widget build(BuildContext context) {
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

    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VitaSplashBranding(appLabel: 'NURSENOW'),
            SizedBox(height: AppSpacing.xl),
            VitaLoadingIndicator(),
          ],
        ),
      ),
    );
  }
}
