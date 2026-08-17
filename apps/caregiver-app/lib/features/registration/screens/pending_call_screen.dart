import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../auth/state/session_notifier.dart';
import '../../auth/state/session_state.dart';
import '../../../app/route_for_status.dart';
import '../../../app/caregiver_bottom_nav.dart';
import '../../../app/whatsapp_help_button.dart';

/// SPEC.md section 12.3: waiting screen shown while verification_status is
/// pending_call. No back navigation to Registration — this is a dead end
/// until the office calls and an admin marks the caregiver call-verified.
class PendingCallScreen extends ConsumerWidget {
  const PendingCallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          title: const Text('NurseJobs'),
          automaticallyImplyLeading: false,
          actions: [
            const WhatsAppHelpButton(),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                ref.read(sessionProvider.notifier).logout().then((_) {
                  navigator.pushNamedAndRemoveUntil('/login', (route) => false);
                });
              },
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: AppColors.background,
        bottomNavigationBar: const CaregiverBottomNav(currentIndex: 0),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.read(sessionProvider.notifier).refreshStatus(),
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
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (name.isNotEmpty) Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (phone.isNotEmpty) Text(phone, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Pull down to refresh',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
