import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// How a [Uri] gets opened. Production opens it with the platform (the phone
/// dialer for `tel:`, WhatsApp for `wa.me`); tests replace this to capture
/// what would have been launched instead of leaving the app.
typedef UriLauncher = Future<bool> Function(Uri uri);

UriLauncher uriLauncher = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// `tel:+919876543210` — starts a call on a phone/softphone-enabled browser.
Uri phoneCallUri(String phone) => Uri(scheme: 'tel', path: phone);

/// A WhatsApp chat with [phone] (`wa.me` wants digits only, no `+`).
Uri whatsAppUri(String phone) => Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}');

/// Call + WhatsApp icon buttons for a person's phone number — so an admin
/// looking at an error can reach the person it happened to in one click.
class ContactButtons extends StatelessWidget {
  final String phone;

  const ContactButtons({super.key, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Call $phone',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.call, size: 20, color: AppColors.success),
          onPressed: () => uriLauncher(phoneCallUri(phone)),
        ),
        IconButton(
          tooltip: 'WhatsApp $phone',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chat, size: 20, color: AppColors.success),
          onPressed: () => uriLauncher(whatsAppUri(phone)),
        ),
      ],
    );
  }
}

/// A phone number with its Call/WhatsApp buttons beside it — what list
/// screens put in their existing Phone column/line, so reaching a person is
/// one click from the list instead of a trip into their detail screen.
/// [label], when set (the mobile card layout), prefixes it like
/// `VitaListCard.kv` does.
class PhoneWithContact extends StatelessWidget {
  final String phone;
  final String? label;

  const PhoneWithContact({super.key, required this.phone, this.label});

  @override
  Widget build(BuildContext context) {
    // Wrap, not Row: on a narrow phone-width card the buttons drop to the
    // next line instead of overflowing.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (label != null)
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: AppTypography.small)),
        Text(phone, style: label != null ? const TextStyle(fontSize: AppTypography.small) : null),
        ContactButtons(phone: phone),
      ],
    );
  }
}
