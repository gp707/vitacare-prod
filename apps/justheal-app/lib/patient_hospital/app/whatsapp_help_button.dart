import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Persistent "reach out for help" entry point — shown on every screen (see
/// each screen's AppBar `actions`/LoginScreen's own placement, since it has
/// no AppBar), so a patient/family or organisation can always message
/// VitaCasaHealth. Mirrors caregiver-app's identical widget (same support
/// number) — kept as a separate per-app copy rather than a shared package
/// widget, consistent with how small app-local UI pieces are handled
/// elsewhere in this codebase.
class WhatsAppHelpButton extends StatelessWidget {
  static const phoneNumber = '917259255869'; // +91 7259255869

  /// Injectable for widget tests — defaults to the real url_launcher call.
  final Future<bool> Function(Uri uri)? launcher;

  /// Style overrides, all defaulted to this button's original compact
  /// look — every existing call site (`const WhatsAppHelpButton()`) across
  /// this app's other AppBars renders identically to before. The login
  /// screen is the one place that overrides these, since it's the only
  /// screen where this is the sole AppBar action and needed to stop being
  /// cut off / hard to spot on narrow screens — see login_screen.dart.
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Size minimumSize;
  final double iconSize;
  final double fontSize;

  const WhatsAppHelpButton({
    super.key,
    this.launcher,
    this.backgroundColor = AppColors.error,
    this.padding = const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    this.margin = const EdgeInsets.only(right: 6),
    this.minimumSize = Size.zero,
    this.iconSize = 12,
    this.fontSize = AppTypography.caption,
  });

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/$phoneNumber');
    bool launched;
    try {
      launched = launcher != null
          ? await launcher!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      showVitaErrorBanner(context, 'Could not open WhatsApp. Message us at +91 7259255869.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filled red pill, not just colored text — plain text on the AppBar
    // was easy for a senior citizen to miss; a solid, high-contrast button
    // is much easier to spot at a glance. Built from ElevatedButton (not
    // ElevatedButton.icon, which forces an 8px icon-label gap) with a
    // hand-built Row so the gap can shrink to fit alongside RateCardButton
    // in this AppBar's tight budget. Wrapped in a right-margin Padding so
    // it never sits flush against the screen edge when it's the last
    // AppBar action.
    final isCompact = minimumSize == Size.zero;
    return Padding(
      padding: margin,
      child: ElevatedButton(
        onPressed: () => _open(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          padding: padding,
          minimumSize: minimumSize,
          tapTargetSize: isCompact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
          visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_in_talk, size: iconSize),
            SizedBox(width: isCompact ? 1 : 6),
            Text('Help', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
