import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../../app/route_for_status.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/messages_bell.dart';

/// SPEC.md section 12.3: waiting screen shown while verification_status is
/// pending_call. No back navigation to Registration — this is a dead end
/// until the office calls and an admin marks the caregiver call-verified.
///
/// Admin's approval does send an FCM push ("Profile approved"), but this
/// app has no foreground/background message listener wired up to react to
/// it — so without something else driving a refresh, a caregiver sitting
/// on this exact screen could stay stuck here long after being approved,
/// with nothing telling them to pull down and check again. Rather than
/// build out full FCM message handling, this screen polls
/// refreshStatus() on its own every [_pollInterval] while it's the one
/// showing — cheap (a single small GET, see SessionNotifier.refreshStatus)
/// and self-contained, so approval is picked up automatically within a
/// few seconds without the caregiver needing to do anything.
class PendingCallScreen extends ConsumerStatefulWidget {
  const PendingCallScreen({super.key});

  @override
  ConsumerState<PendingCallScreen> createState() => _PendingCallScreenState();
}

class _PendingCallScreenState extends ConsumerState<PendingCallScreen> {
  static const _pollInterval = Duration(seconds: 15);
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      // Silently ignored either way — a failed background tick just tries
      // again next interval, same fail-open contract as loadSession.
      ref.read(sessionProvider.notifier).refreshStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePullToRefresh() async {
    final succeeded = await ref.read(sessionProvider.notifier).refreshStatus();
    // Only a manual pull gets error feedback — the caregiver actively
    // asked for a check just now and deserves to know it didn't reach the
    // server, rather than silently seeing nothing happen and wondering
    // whether their pull even registered.
    if (!succeeded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check for updates. Please check your connection and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next is SessionAuthenticated && next.verificationStatus != VerificationStatus.pendingCall) {
        Navigator.of(context).pushNamedAndRemoveUntil(routeForStatus(next), (route) => false);
      }
    });

    final name = session is SessionAuthenticated ? session.fullName : '';
    final phone = session is SessionAuthenticated ? session.phone : '';

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const VitaAppBarTitle('NurseJobs'),
          automaticallyImplyLeading: false,
          // Logout lives only on the Profile screen now (moved to the
          // bottom of the page there) — no longer duplicated in every
          // screen's AppBar. Reachable from here via the bottom nav's
          // Profile tab, same as from any other screen.
          actions: caregiverAppBarActions(showBell: true),
        ),
        backgroundColor: AppColors.background,
        bottomNavigationBar: const CaregiverBottomNav(currentIndex: 0),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _handlePullToRefresh,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const Icon(Icons.phone_in_talk, size: 64, color: AppColors.statusPendingCall),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Thank you for registering! You will receive a call from our '
                  'office shortly to verify your phone number.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppTypography.subtitle),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (name.isNotEmpty) Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (phone.isNotEmpty) Text(phone, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Pull down to refresh',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
