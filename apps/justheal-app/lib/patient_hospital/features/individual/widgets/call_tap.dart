import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'package:nursenow_app/analytics/analytics.dart';

/// Opens a URI (here always `tel:`) in the phone's own app. A provider so widget
/// tests can capture the call instead of leaving the app.
final phoneLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Makes [child] (a caregiver's name or phone number) tappable: it opens the
/// phone's dialer with [phone] filled in, ready to call. If the device can't
/// place calls, a banner shows the number so it can be dialled by hand.
class CallTap extends ConsumerWidget {
  final String phone;
  final String name;
  final Widget child;

  const CallTap({super.key, required this.phone, required this.name, required this.child});

  Future<void> _call(BuildContext context, WidgetRef ref) async {
    Analytics.tap('individual', 'requirement_posted', 'call_caregiver');
    bool launched;
    try {
      launched = await ref.read(phoneLauncherProvider)(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      showVitaErrorBanner(context, 'Could not open the dialer. Call $phone directly.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Call $name',
      child: InkWell(
        onTap: () => _call(context, ref),
        borderRadius: BorderRadius.circular(4),
        child: child,
      ),
    );
  }
}

/// A WhatsApp chat with [phone] (`wa.me` wants digits only, with the country code).
Uri whatsAppUri(String phone) => Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}');

/// Makes [child] tappable: it opens a WhatsApp chat with [phone]. If WhatsApp can't be
/// opened, a banner shows the number so it can be messaged by hand.
class WhatsAppTap extends ConsumerWidget {
  final String phone;
  final String name;
  final Widget child;

  const WhatsAppTap({super.key, required this.phone, required this.name, required this.child});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    Analytics.tap('individual', 'requirement_posted', 'whatsapp_caregiver');
    bool launched;
    try {
      launched = await ref.read(phoneLauncherProvider)(whatsAppUri(phone));
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      showVitaErrorBanner(context, 'Could not open WhatsApp. Message $phone directly.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'WhatsApp $name',
      child: InkWell(
        key: const Key('whatsapp-tap'),
        onTap: () => _open(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

/// A caregiver's phone number as one row: the number (tap to call) and a WhatsApp chip
/// (tap to chat). Wraps onto a second line on a narrow screen or with large text.
class PhoneContactRow extends StatelessWidget {
  final String phone;
  final String name;

  const PhoneContactRow({super.key, required this.phone, required this.name});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: 2,
      children: [
        CallTap(
          phone: phone,
          name: name,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.call, size: 14, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(phone, style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ),
        WhatsAppTap(
          phone: phone,
          name: name,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.12),
              border: Border.all(color: const Color(0xFF25D366)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat, size: 14, color: Color(0xFF128C7E)),
                SizedBox(width: 4),
                Text('WhatsApp', style: TextStyle(color: Color(0xFF128C7E), fontWeight: FontWeight.w600, fontSize: AppTypography.small)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
