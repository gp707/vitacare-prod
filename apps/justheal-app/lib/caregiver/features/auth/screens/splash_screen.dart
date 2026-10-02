import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../app/route_for_status.dart';
import '../../../core/providers.dart';

/// Routes safe to restore on refresh once authenticated — every route
/// registered in router.dart's buildCaregiverRoutes() map except the
/// pre-auth ones ('/caregiver', '/caregiver/login', '/caregiver/register').
/// All are argument-free, and bottom-nav tabs (Jobs/MyJobs/Profile) are
/// reachable regardless of verification_status per CLAUDE.md, so restoring
/// e.g. "/caregiver/jobs" is valid even for a pending_call caregiver. Kept
/// in sync with router.dart by hand, same convention as admin-web's
/// equivalent set.
const _restorableRoutes = {'/caregiver/pending-call', '/caregiver/profile', '/caregiver/jobs', '/caregiver/my-jobs'};

/// NOTE: this screen is registered at the bare '/caregiver' route, which
/// nothing in the merged JustHeal app actually navigates to anymore — real
/// entry points are '/caregiver/register' (the "Caregivers Registration"
/// button) and '/caregiver/login' (the "Already registered? Login" link),
/// both reached directly from the host app's own screens, never through
/// here. Version/maintenance gating therefore lives solely in the host's
/// own splash screen now (lib/patient_hospital/.../splash_screen.dart) —
/// it's the one real entry point for every user, caregiver or patient/
/// hospital alike (see CLAUDE.md's "Merged into one binary with
/// NurseJobs" and migration 074). This screen is kept only so the route
/// still resolves to something sane if ever reached directly (e.g. a
/// stale bookmark), and still does its own OTP-mode/apply-by-window
/// fetch since those stay genuinely per-app (see the registration/login
/// screens' own initState, which do the same fetch independently now that
/// this screen is no longer guaranteed to run first).
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

  Future<void> _checkAuthConfigThenLoadSession() async {
    // Both calls are unauthenticated and fail open, so they're safe to run
    // in parallel rather than sequentially.
    final results = await Future.wait([
      ref.read(authConfigRepositoryProvider).isOtpEnabled(),
      ref.read(jobSettingsRepositoryProvider).getApplyByWindowDays(),
    ]);
    if (!mounted) return;

    final otpEnabled = results[0] as bool;
    final applyByWindowDays = results[1] as int;
    ref.read(otpModeProvider.notifier).state = otpEnabled;
    ref.read(applyByWindowDaysProvider.notifier).state = applyByWindowDays;

    ref.read(sessionProvider.notifier).loadSession();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionUnauthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/caregiver/login', (route) => false);
      } else if (next is SessionAuthenticated) {
        final restoreRoute = widget.initialDeepLinkRoute;
        final target = restoreRoute != null && _restorableRoutes.contains(restoreRoute)
            ? restoreRoute
            : routeForStatus(next);
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
            const VitaSplashBranding(appLabel: 'NURSEJOBS'),
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
