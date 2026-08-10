import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../features/auth/state/session_notifier.dart';
import '../features/auth/state/session_state.dart';

/// Checks for a stored session and redirects to /login or /dashboard.
/// SPEC.md's admin screen list (13.1) doesn't name a distinct splash
/// screen, but this bootstrap step is still needed.
class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});

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
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      } else if (next is AdminSessionAuthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (route) => false);
      }
    });

    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: VitaLoadingIndicator()),
    );
  }
}
