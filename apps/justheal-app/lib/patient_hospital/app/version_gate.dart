import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nursenow_app/caregiver/core/providers.dart' as caregiver;
import 'package:nursenow_app/caregiver/features/auth/state/session_notifier.dart' as caregiver_session;
import 'package:nursenow_app/caregiver/features/auth/state/session_state.dart' as caregiver_session_state;
import '../core/providers.dart';
import '../core/version/app_version_repository.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';
import 'update_required_screen.dart';

/// The version check for the caregiver flow's own session: same endpoint, but through the caregiver's
/// API client, so the caregiver's token tells the server who is asking.
final caregiverAppVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return AppVersionRepository(ref.watch(caregiver.apiClientProvider).dio);
});

/// Blocks the whole app with the "Update required" screen when the signed-in account is bound by a
/// forced minimum version it does not meet.
///
/// The cold-launch check (SplashScreen) happens before anyone is known, so it can only apply a minimum
/// that is meant for everyone. A minimum aimed at selected categories or accounts needs to know WHO is
/// asking, so this gate asks again every time an account becomes signed in — by logging in, by
/// registering, or by an old session being restored — through that account's own API client (its token
/// identifies it). Because it also covers sign-in, being logged out at launch is no way around it.
///
/// Fails open like the launch check: an error means "no update needed". The overlay cannot be dismissed;
/// the user updates (or closes the app).
class VersionGate extends ConsumerStatefulWidget {
  final Widget child;

  /// Injectable for widget tests — defaults to the real url_launcher call.
  final Future<bool> Function(Uri uri)? launcher;

  const VersionGate({super.key, required this.child, this.launcher});

  @override
  ConsumerState<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends ConsumerState<VersionGate> {
  UpdateRequiredInfo? _info;
  // Only the newest answer counts: a slow reply for an earlier sign-in must not overwrite a later one.
  int _generation = 0;

  Future<void> _check(AppVersionRepository repository) async {
    final generation = ++_generation;
    final info = await repository.checkForUpdate();
    if (!mounted || generation != _generation || info == null) return;
    setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionAuthenticated && previous is! SessionAuthenticated) {
        _check(ref.read(appVersionRepositoryProvider));
      }
    });
    ref.listen<caregiver_session_state.SessionState>(caregiver_session.sessionProvider, (previous, next) {
      if (next is caregiver_session_state.SessionAuthenticated && previous is! caregiver_session_state.SessionAuthenticated) {
        _check(ref.read(caregiverAppVersionRepositoryProvider));
      }
    });

    final info = _info;
    if (info == null) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: UpdateRequiredScreen(
            key: const Key('version-gate-update-required'),
            storeUrl: info.storeUrl,
            message: info.message,
            launcher: widget.launcher,
          ),
        ),
      ],
    );
  }
}
