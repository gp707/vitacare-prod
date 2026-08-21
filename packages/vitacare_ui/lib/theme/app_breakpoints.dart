import 'package:flutter/material.dart';

/// Standard Material-ish width breakpoints, shared by every app so a
/// "mobile" layout means the same thing everywhere. A width strictly below
/// [mobile] is a phone; strictly below [tablet] is a tablet/small window;
/// [tablet] and above is desktop/laptop.
class AppBreakpoints {
  AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 1024;
}

/// `context.isMobile` etc. — reads the current [MediaQuery] width once per
/// call site instead of every screen hand-rolling its own
/// `MediaQuery.sizeOf(context).width < 600` check.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  bool get isMobile => screenWidth < AppBreakpoints.mobile;
  bool get isTablet => screenWidth >= AppBreakpoints.mobile && screenWidth < AppBreakpoints.tablet;
  bool get isDesktop => screenWidth >= AppBreakpoints.tablet;

  /// True below the tablet breakpoint — the point at which a permanent
  /// sidebar stops fitting comfortably and screens should switch to a
  /// single-column/drawer-based layout.
  bool get isCompact => screenWidth < AppBreakpoints.tablet;

  /// Clamps a dialog's preferred content width to what the viewport can
  /// actually fit, leaving [margin] total (both sides combined) so the
  /// dialog never touches the screen edges. `AlertDialog` doesn't shrink a
  /// fixed-width child on its own, so every dialog with a hardcoded
  /// `SizedBox(width: ...)` needs this instead of the raw pixel value.
  double dialogWidth(double preferred, {double margin = 48}) {
    return preferred < screenWidth - margin ? preferred : screenWidth - margin;
  }
}
