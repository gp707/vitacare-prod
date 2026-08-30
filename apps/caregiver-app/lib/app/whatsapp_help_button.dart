import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    // Compact padding/density — this button shares AppBar space with a
    // filter icon and Logout, so the wide default ElevatedButton padding
    // overflows a typical phone-width AppBar once all three are present.
    return Padding(
      padding: EdgeInsets.zero,
      child: ElevatedButton.icon(
        onPressed: () => _open(context),
        icon: const Icon(Icons.phone_in_talk, size: 16),
        label: const Text('Click for Help', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
    );
  }
}
