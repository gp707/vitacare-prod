import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Shown instead of the normal app when an admin has switched NurseJobs
/// into maintenance mode (see AppMaintenanceRepository.checkForMaintenance,
/// called from SplashScreen before anything else loads, same launch-time/
/// fail-open contract as the version check). No way to dismiss or navigate
/// past this — unlike UpdateRequiredScreen there's no external action to
/// take (nothing to update), so this offers a Retry button to re-check
/// instead of a store link.
class MaintenanceScreen extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const MaintenanceScreen({super.key, this.message, required this.onRetry});

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
                const Icon(Icons.build_circle_outlined, size: 64, color: AppColors.primary),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Under Maintenance',
                  style: TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message ?? 'NurseJobs is temporarily unavailable for maintenance. Please check back shortly.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
