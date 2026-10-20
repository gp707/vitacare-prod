import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Small brand mark shown next to every screen's AppBar title — just the
/// icon (not the full VitaSplashBranding lockup with wordmark/tagline,
/// which is reserved for splash/login, where the brand is the whole
/// point). Sized to visually match the weight of the title text next to
/// it (not eating AppBar real estate, just reading as equally prominent
/// as the words beside it) — sits in the `title` slot (not `leading`), so
/// it never displaces a screen's back button.
///
/// [onTripleTap], when provided, turns the icon into a hidden logout
/// trigger — 3 taps within [tripleTapWindow] of each other fires it (any
/// gap longer than that resets the count back to 1, so idle taps spread
/// out over time never accumulate). This replaced a visible Logout button
/// on request — every authenticated JustHeal screen passes its own
/// logout callback here instead. Left null (the default) for admin-web
/// and every pre-auth screen (registration), where this icon is just a
/// static brand mark same as before.
class VitaAppBarTitle extends StatefulWidget {
  final String title;
  final VoidCallback? onTripleTap;
  final Duration tripleTapWindow;

  const VitaAppBarTitle(
    this.title, {
    super.key,
    this.onTripleTap,
    this.tripleTapWindow = const Duration(seconds: 2),
  });

  @override
  State<VitaAppBarTitle> createState() => _VitaAppBarTitleState();
}

class _VitaAppBarTitleState extends State<VitaAppBarTitle> {
  int _tapCount = 0;
  DateTime? _lastTapAt;

  void _handleTap() {
    final now = DateTime.now();
    final lastTapAt = _lastTapAt;
    _tapCount = (lastTapAt != null && now.difference(lastTapAt) <= widget.tripleTapWindow) ? _tapCount + 1 : 1;
    _lastTapAt = now;
    if (_tapCount >= 3) {
      _tapCount = 0;
      _lastTapAt = null;
      widget.onTripleTap?.call();
    }
  }

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
        final logo = Image.asset(
          'packages/vitacare_ui/assets/branding/logo_icon.webp',
          width: logoSize,
          height: logoSize,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLogo) ...[
              widget.onTripleTap == null
                  ? logo
                  : GestureDetector(behavior: HitTestBehavior.opaque, onTap: _handleTap, child: logo),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(child: Text(widget.title, overflow: TextOverflow.ellipsis)),
          ],
        );
      },
    );
  }
}
