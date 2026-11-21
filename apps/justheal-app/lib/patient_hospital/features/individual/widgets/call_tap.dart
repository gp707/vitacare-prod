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
  /// On a dark (solid green) card: white number, and a white WhatsApp chip.
  final bool onDark;

  const PhoneContactRow({super.key, required this.phone, required this.name, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: 2,
      children: [
        // The number is a button (a pill, like the WhatsApp one next to it), not just a link.
        CallTap(
          phone: phone,
          name: name,
          child: Container(
            key: const Key('call-button'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: onDark ? Colors.white : AppColors.primary.withValues(alpha: 0.08),
              border: Border.all(color: onDark ? Colors.white : AppColors.primary),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call, size: 15, color: onDark ? AppColors.success : AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(phone,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: onDark ? AppColors.success : AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
        // Icon only: the WhatsApp glyph (the screen-reader label still says "WhatsApp <name>").
        WhatsAppTap(
          phone: phone,
          name: name,
          child: Container(
            key: const Key('whatsapp-icon-button'),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onDark ? Colors.white : const Color(0xFF25D366).withValues(alpha: 0.12),
              border: Border.all(color: onDark ? Colors.white : const Color(0xFF25D366)),
              shape: BoxShape.circle,
            ),
            child: const WhatsAppGlyph(size: 24),
          ),
        ),
      ],
    );
  }
}

/// A small WhatsApp-style mark (green speech bubble with a handset in it). Drawn here because the
/// icon sets the app has no brand icon.
class WhatsAppGlyph extends StatelessWidget {
  final double size;

  const WhatsAppGlyph({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('whatsapp-glyph'),
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _BubblePainter()),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.04),
            child: Icon(Icons.call, size: size * 0.55, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF25D366);
    final r = size.width / 2;
    canvas.drawCircle(Offset(r, r), r * 0.92, paint);
    // the bubble's tail, bottom-left
    final tail = Path()
      ..moveTo(size.width * 0.04, size.height * 0.98)
      ..lineTo(size.width * 0.12, size.height * 0.62)
      ..lineTo(size.width * 0.38, size.height * 0.86)
      ..close();
    canvas.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
