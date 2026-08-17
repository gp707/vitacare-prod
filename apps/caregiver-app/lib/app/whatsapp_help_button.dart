import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Persistent "reach out for help" entry point — shown in every main
/// screen's AppBar regardless of verification status, so a caregiver can
/// always message VitaCasaHealth about their job, profile, or anything
/// else, no matter where they are in the app.
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

  // WhatsApp's brand green — a plain white outline icon blended into the
  // rest of the AppBar's white icons/text and was easy to miss. A filled
  // green badge plus a visible "Help" label reads as an obviously
  // tappable, distinct action instead.
  static const _whatsAppGreen = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _open(context),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      icon: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: _whatsAppGreen, shape: BoxShape.circle),
        child: const Icon(Icons.chat, size: 14, color: Colors.white),
      ),
      label: const Text('Help', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
