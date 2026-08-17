import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Shown instead of the normal app when the caregiver's installed build is
/// below the admin-configured minimum for their platform (see
/// AppVersionRepository.checkForUpdate, called from SplashScreen before
/// anything else loads). No way to dismiss or navigate past this — the
/// caregiver must update to continue.
class UpdateRequiredScreen extends StatelessWidget {
  final String? storeUrl;
  final String? message;

  /// Injectable for widget tests — defaults to the real url_launcher call.
  final Future<bool> Function(Uri uri)? launcher;

  const UpdateRequiredScreen({super.key, this.storeUrl, this.message, this.launcher});

  Future<void> _openStore(BuildContext context) async {
    final url = storeUrl;
    if (url == null) return;
    bool launched;
    try {
      final uri = Uri.parse(url);
      launched = launcher != null ? await launcher!(uri) : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the app store.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 64, color: AppColors.primary),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Update Required',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message ?? 'A new version of NurseJobs is available. Please update to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (storeUrl != null)
                  ElevatedButton(
                    onPressed: () => _openStore(context),
                    child: const Text('Update Now'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
