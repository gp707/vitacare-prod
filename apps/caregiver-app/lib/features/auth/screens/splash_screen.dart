import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/session_notifier.dart';
import '../state/session_state.dart';
import '../../../app/route_for_status.dart';
import '../../../app/update_required_screen.dart';
import '../../../core/providers.dart';
import '../../../core/version/app_version_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

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
    final updateInfo = await ref.read(appVersionRepositoryProvider).checkForUpdate();
    if (!mounted) return;
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
        Navigator.of(context).pushNamedAndRemoveUntil(routeForStatus(next), (route) => false);
      }
    });

    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'NurseJobs',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            SizedBox(height: AppSpacing.lg),
            VitaLoadingIndicator(),
          ],
        ),
      ),
    );
  }
}
