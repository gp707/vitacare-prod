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

  const WhatsAppHelpButton({super.key, this.launcher});

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Message us at +91 7259255869.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filled red pill, not just colored text — plain text on the AppBar
    // was easy for a senior citizen to miss; a solid, high-contrast button
    // is much easier to spot at a glance.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: ElevatedButton.icon(
        onPressed: () => _open(context),
        icon: const Icon(Icons.phone_in_talk, size: 18),
        label: const Text('Click for Help', style: TextStyle(fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
    );
  }
}
