import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Small brand mark shown next to every screen's AppBar title — just the
/// icon (not the full VitaSplashBranding lockup with wordmark/tagline,
/// which is reserved for splash/login, where the brand is the whole
/// point). Sized to visually match the weight of the title text next to
/// it (not eating AppBar real estate, just reading as equally prominent
/// as the words beside it) — sits in the `title` slot (not `leading`), so
/// it never displaces a screen's back button.
class VitaAppBarTitle extends StatelessWidget {
  final String title;

  const VitaAppBarTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final titleFontSize =
        AppBarTheme.of(context).titleTextStyle?.fontSize ?? Theme.of(context).textTheme.titleLarge?.fontSize ?? 22;
    // A glyph's cap-height reads smaller than its declared font size, so a
    // logo sized to the raw font size looks tiny next to the text — scaling
    // up is what actually makes the two read as the same visual weight.
    final logoSize = titleFontSize * 1.4;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The AppBar's title slot can be squeezed very narrow when a
        // screen has several actions (Rate Card/Help/bell/menu) sharing
        // the same row — drop the logo rather than overflow once there
        // isn't room for it plus at least a sliver of the title itself.
        final showLogo = constraints.maxWidth >= logoSize + AppSpacing.sm + 24;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLogo) ...[
              Image.asset('packages/vitacare_ui/assets/branding/logo_icon.png', width: logoSize, height: logoSize),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        );
      },
    );
  }
}
