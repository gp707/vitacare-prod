import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/read_only_admin.dart';

/// Wraps a route a read-only admin may not open (Settings, messages, push
/// notifications) — a typed or bookmarked URL lands here instead of the page.
class BlockedForReadOnly extends ConsumerWidget {
  final Widget child;

  const BlockedForReadOnly({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isReadOnlyAdminProvider)) return child;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: AppSpacing.md),
              const Text(
                "Your account doesn't have access to this page.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
