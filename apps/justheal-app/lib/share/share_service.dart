import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'package:nursenow_app/analytics/analytics.dart';

/// Opens the phone's share sheet with [text]. Swappable so tests never open a real sheet.
final shareSheetProvider = Provider<Future<void> Function(String text)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);

/// Opens a URL outside the app (used for WhatsApp). Swappable for tests.
final shareUrlLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// `https://wa.me/?text=...` — opens WhatsApp's own "choose a chat" screen with the message
/// already typed, so sharing is two taps.
Uri whatsAppShareUri(String text) => Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');

/// Shares [text] straight into WhatsApp; if WhatsApp can't be opened (not installed), falls
/// back to the general share sheet so the person can still send it some other way.
Future<void> shareViaWhatsApp(BuildContext context, WidgetRef ref, String text,
    {required String flow, required String screen, required String action}) async {
  Analytics.tap(flow, screen, action);
  var launched = false;
  try {
    launched = await ref.read(shareUrlLauncherProvider)(whatsAppShareUri(text));
  } catch (_) {
    launched = false;
  }
  if (!launched && context.mounted) {
    await shareViaSheet(context, ref, text, flow: flow, screen: screen, action: '${action}_fallback', report: false);
  }
}

/// Shares [text] through the phone's share sheet (any app).
Future<void> shareViaSheet(BuildContext context, WidgetRef ref, String text,
    {required String flow, required String screen, required String action, bool report = true}) async {
  if (report) Analytics.tap(flow, screen, action);
  try {
    await ref.read(shareSheetProvider)(text);
  } catch (_) {
    if (context.mounted) showVitaErrorBanner(context, 'Could not open sharing. Please try again.');
  }
}
