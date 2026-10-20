import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Tap-counting for a hidden triple-tap gesture, shared by [VitaAppBarTitle]
/// and [VitaAppBar] (both via the private [_BrandIcon]) — any gap longer
/// than [window] between consecutive taps resets the count back to 1, so
/// idle taps spread out over time never accumulate into an accidental
/// trigger.
class _TripleTapCounter {
  final Duration window;
  int _tapCount = 0;
  DateTime? _lastTapAt;

  _TripleTapCounter(this.window);

  /// Returns true exactly once, the moment a triple-tap completes.
  bool registerTap() {
    final now = DateTime.now();
    final lastTapAt = _lastTapAt;
    _tapCount = (lastTapAt != null && now.difference(lastTapAt) <= window) ? _tapCount + 1 : 1;
    _lastTapAt = now;
    if (_tapCount >= 3) {
      _tapCount = 0;
      _lastTapAt = null;
      return true;
    }
    return false;
  }
}

/// The brand icon alone — sized to match the weight of an AppBar title,
/// with the same optional hidden-triple-tap-to-logout gesture described on
/// [VitaAppBarTitle]. Private: [VitaAppBarTitle] and [VitaAppBar] are the
/// two public shapes this icon appears in, combined with the title text
/// differently in each (side-by-side vs. stacked in its own row below).
class _BrandIcon extends StatefulWidget {
  final VoidCallback? onTripleTap;
  final Duration tripleTapWindow;
  // Overrides the auto-derived size below — [VitaAppBar] passes its own
  // larger, fixed value, since that icon no longer shares its row with
  // title text and can afford to read as a more deliberate, prominent
  // brand mark rather than one sized just to match adjacent text.
  final double? size;

  const _BrandIcon({this.onTripleTap, this.tripleTapWindow = const Duration(seconds: 2), this.size});

  @override
  State<_BrandIcon> createState() => _BrandIconState();
}

class _BrandIconState extends State<_BrandIcon> {
  late final _counter = _TripleTapCounter(widget.tripleTapWindow);

  void _handleTap() {
    if (_counter.registerTap()) widget.onTripleTap?.call();
  }

  // A glyph's cap-height reads smaller than its declared font size, so a
  // logo sized to the raw font size looks tiny next to the text — scaling
  // up is what actually makes the two read as the same visual weight.
  // Used by VitaAppBarTitle (icon+text sharing one row); VitaAppBar passes
  // its own fixed [size] instead, since that icon has no adjacent text to
  // match the weight of.
  double _defaultSize(BuildContext context) {
    final titleFontSize =
        AppBarTheme.of(context).titleTextStyle?.fontSize ?? Theme.of(context).textTheme.titleLarge?.fontSize ?? 22;
    return titleFontSize * 1.4;
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = widget.size ?? _defaultSize(context);
    final logo = Image.asset(
      'packages/vitacare_ui/assets/branding/logo_icon.webp',
      width: logoSize,
      height: logoSize,
    );
    return widget.onTripleTap == null
        ? logo
        : GestureDetector(
            // A stable, type-independent key — VitaAppBar's own subtree
            // also contains the AppBar's actions (TextZoomButton/
            // RateCardButton/WhatsAppHelpButton/bell/…), each wrapping its
            // own GestureDetector, so a find.byType(GestureDetector) scoped
            // only to VitaAppBar/VitaAppBarTitle is ambiguous whenever any
            // actions are passed. This key lets a test target this one
            // specific tap handler unambiguously regardless of actions.
            key: const ValueKey('vitaAppBarBrandIconTap'),
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: logo,
          );
  }
}

/// Small brand mark shown next to every screen's AppBar title — just the
/// icon (not the full VitaSplashBranding lockup with wordmark/tagline,
/// which is reserved for splash/login, where the brand is the whole
/// point). Sits in the `title` slot (not `leading`), so it never displaces
/// a screen's back button.
///
/// [onTripleTap], when provided, turns the icon into a hidden logout
/// trigger — 3 taps within [tripleTapWindow] of each other fires it. This
/// replaced a visible Logout button on request — every authenticated
/// JustHeal screen passes its own logout callback here instead. Left null
/// (the default) for admin-web and every pre-auth screen (registration),
/// where this icon is just a static brand mark same as before.
///
/// Icon and title share one row here — see [VitaAppBar] for the two-row
/// layout (icon + actions on one row, title on its own row below) used by
/// every JustHeal screen that also carries several AppBar actions (Rate
/// Card/Help/bell/…), where a long title sharing this one row with those
/// actions was getting squeezed down to just a few visible characters.
class VitaAppBarTitle extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final titleFontSize =
        AppBarTheme.of(context).titleTextStyle?.fontSize ?? Theme.of(context).textTheme.titleLarge?.fontSize ?? 22;
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
              _BrandIcon(onTripleTap: onTripleTap, tripleTapWindow: tripleTapWindow),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        );
      },
    );
  }
}

/// Two-row AppBar: the icon (with its own optional triple-tap-to-logout,
/// same as [VitaAppBarTitle]) shares the main toolbar row with [actions],
/// and [title] gets its own full-width row underneath, in a smaller font.
///
/// Replaces plain `AppBar(title: VitaAppBarTitle(...), actions: ...)`
/// wherever a screen also carries several AppBar actions (Rate Card/Help/
/// bell/A+/…) — those actions were leaving so little width for the title
/// slot that titles like "Requirement Posted" rendered as "Requirem…".
/// Giving the title its own row removes that squeeze entirely, so it only
/// ever truncates for a title that's genuinely too long for the full
/// screen width (the ellipsis stays as a safety net, not the normal case).
class VitaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onTripleTap;
  final Duration tripleTapWindow;
  // Rendered right after the title text, on the same (second) row — e.g. a
  // VitaStatusBadge next to "My Profile".
  final Widget? titleTrailing;
  // A further row below the title row — e.g. a TabBar. Its own
  // preferredSize.height is folded into this AppBar's total height.
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  const VitaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onTripleTap,
    this.tripleTapWindow = const Duration(seconds: 2),
    this.titleTrailing,
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  static const double _titleRowHeight = 36;
  // Fixed rather than auto-derived from titleTextStyle (see _BrandIcon's
  // own default) — this icon no longer shares its row with title text, so
  // it reads better sized as a deliberate, consistent brand mark instead
  // of whatever happened to match a font size. Slightly larger than the
  // ~31 the old shared-row derivation produced, now that it has a full,
  // uncontested row to sit in.
  static const double _iconSize = 34;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + _titleRowHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final titleColor = AppBarTheme.of(context).foregroundColor ?? Theme.of(context).colorScheme.onSurface;

    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: _BrandIcon(onTripleTap: onTripleTap, tripleTapWindow: tripleTapWindow, size: _iconSize),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_titleRowHeight + (bottom?.preferredSize.height ?? 0)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.w600, color: titleColor),
                    ),
                  ),
                  if (titleTrailing != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    titleTrailing!,
                  ],
                ],
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}
