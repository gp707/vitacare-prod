import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shows a dismissible red banner pinned to the top of the screen (below
/// the AppBar, via [ScaffoldMessenger]'s MaterialBanner slot) for a failed
/// action — a server error, or any "failed to accept/reject/save/cancel"
/// case. Auto-dismisses after 5 seconds, or immediately if the user taps
/// its own close button — whichever comes first. Used instead of a bottom
/// SnackBar for failures specifically, so they read as an alert that
/// demands attention rather than a passing toast.
void showVitaErrorBanner(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  // Never stack a second banner on top of one still showing.
  messenger.clearMaterialBanners();
  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: AppColors.error,
      content: Text(message, style: const TextStyle(color: Colors.white)),
      actions: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 20),
          tooltip: 'Dismiss',
          onPressed: messenger.hideCurrentMaterialBanner,
        ),
      ],
    ),
  );
  // hideCurrentMaterialBanner() is a safe no-op if the user already
  // dismissed it (or a newer banner replaced it) before this fires.
  Timer(const Duration(seconds: 5), messenger.hideCurrentMaterialBanner);
}
