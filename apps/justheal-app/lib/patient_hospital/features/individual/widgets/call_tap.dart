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
