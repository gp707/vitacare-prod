import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Company logo lockup (icon + "Vitacasa Health" wordmark) + tagline, shown
/// on every app's splash/loading screen before the session resolves.
/// [appLabel] identifies which product this is (e.g. "NURSEJOBS") — the
/// company brand is the visual hero here, the product name is a small
/// secondary caption underneath it.
class VitaSplashBranding extends StatelessWidget {
  final String appLabel;
  final double logoWidth;

  const VitaSplashBranding({super.key, required this.appLabel, this.logoWidth = 200});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('packages/vitacare_ui/assets/branding/logo_lockup.png', width: logoWidth),
        const SizedBox(height: AppSpacing.sm),
        Text(
          appLabel,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Helping Hands, Healing Hearts',
          style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
