import 'package:flutter/material.dart';

/// Font family, weight, and font-size scale shared by all 3 apps
/// (admin-web, caregiver-app, nursenow-app). A single scale is used
/// everywhere — every screen in every app maps its text to the nearest
/// step here rather than picking its own one-off size, so the same kind of
/// text (a caption, a body line, a section title, ...) reads at the same
/// size no matter which app or screen it's on.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Inter';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Smallest text on the page — fine print, a single-word tag.
  static const double caption = 11;

  /// Secondary/supporting text — timestamps, helper text, chip labels.
  static const double small = 12;

  /// Default running text — the size most body copy and field values use.
  static const double body = 14;

  /// A slightly emphasized line — a card's headline value, a list item's
  /// primary text.
  static const double subtitle = 16;

  /// A dialog title or a section heading within a screen.
  static const double title = 18;

  /// A prominent heading, larger than a section title but not the page's
  /// own title.
  static const double heading = 22;

  /// A screen/page's own title.
  static const double display = 24;

  /// Reserved for the rare very-large figure (e.g. a splash/branding
  /// wordmark) — not a general-purpose size.
  static const double jumbo = 28;
}
