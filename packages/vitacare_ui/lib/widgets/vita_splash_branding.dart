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

  /// Defaults to the original company tagline so admin-web's own splash
  /// (VITACARE ADMIN) renders unchanged — JustHeal's two splash screens
  /// (host + ported caregiver) override this to "By VitaCasaHealth.in"
  /// instead, matching the byline under the login screen's own title.
  final String tagline;

  const VitaSplashBranding({
    super.key,
    required this.appLabel,
    this.logoWidth = 200,
    this.tagline = 'Helping Hands, Healing Hearts',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('packages/vitacare_ui/assets/branding/logo_lockup.webp', width: logoWidth),
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
        Text(
          tagline,
          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
