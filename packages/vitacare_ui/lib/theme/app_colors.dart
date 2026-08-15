import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary
  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFFDBEAFE);
  static const primaryDark = Color(0xFF1E40AF);

  // Status
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const error = Color(0xFFDC2626);
  static const info = Color(0xFF0891B2);

  // Verification status colors
  static const statusPendingCall = Color(0xFFF59E0B);
  static const statusAvailable = Color(0xFF16A34A); // Green — verified & available
  static const statusAssigned = Color(0xFF2563EB); // Blue — currently assigned
  static const statusRejected = Color(0xFFDC2626);

  // Neutral
  static const background = Color(0xFFF9FAFB);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}
