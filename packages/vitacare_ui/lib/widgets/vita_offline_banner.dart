import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shown when the device has no connectivity. Mobile-only in practice
/// (CLAUDE.md: mutations require internet, no offline queueing) but the
/// widget itself is harmless to include in the shared package.
class VitaOfflineBanner extends StatelessWidget {
  const VitaOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      color: AppColors.warning,
      child: const Text(
        "You're offline. Some actions may not work.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}
