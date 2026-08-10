import 'package:flutter/material.dart';

/// Font family + weight scale only. Each app defines its own text sizes
/// (mobile and web need different scales) — see SPEC.md section 2.3.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Inter';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
