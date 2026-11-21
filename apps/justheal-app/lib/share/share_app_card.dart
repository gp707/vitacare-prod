import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import 'share_messages.dart';
import 'share_service.dart';

/// "Tell a friend about JustHeal": one green **Share on WhatsApp** button (two taps to a
/// ready message) and a **More** button for any other app. The wording follows who is
/// sharing ([audience]). [flow]/[screen] only label the analytics tap.
///
/// [compact] is the slightly tighter inline version used at happy moments (after being accepted,
/// after the first applicants arrive); the full version lives on the Profile screens.
class ShareAppCard extends ConsumerWidget {
  final ShareAudience audience;
  final String flow;
  final String screen;
  final bool compact;

  const ShareAppCard({
    super.key,
    required this.audience,
    required this.flow,
    required this.screen,
    this.compact = false,
  });

  String get _headline => switch (audience) {
        ShareAudience.caregiver => 'Know a nurse or caregiver looking for work?',
        ShareAudience.individual => 'Know a family that needs a nurse or caregiver?',
        ShareAudience.organisation => 'Know a hospital or clinic that is hiring?',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = appInviteMessage(audience);
    final whatsapp = FilledButton.icon(
      key: const Key('share-app-whatsapp'),
      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
      onPressed: () => shareViaWhatsApp(context, ref, message, flow: flow, screen: screen, action: 'share_app_whatsapp'),
      icon: const Icon(Icons.chat, size: 18),
      label: const Text('Share on WhatsApp'),
    );
    final more = OutlinedButton.icon(
      key: const Key('share-app-more'),
      onPressed: () => shareViaSheet(context, ref, message, flow: flow, screen: screen, action: 'share_app_more'),
      icon: const Icon(Icons.share, size: 18),
      label: const Text('More'),
    );
    return Container(
      key: const Key('share-app-card'),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF1FBF5),
        border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Small, regular weight and always one line: scaled down a little rather than wrapped.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _headline,
              key: const Key('share-app-headline'),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontWeight: FontWeight.normal, fontSize: AppTypography.small),
            ),
          ),
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
          // A Wrap so the buttons stack on a narrow screen or with large text.
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [whatsapp, more]),
        ],
      ),
    );
  }
}

/// A small "Share this job" link for a job card (caregivers): sends the job's city, shift
/// and plain salary plus the store link — never an address, name or phone number.
class ShareJobButton extends ConsumerWidget {
  final String message;
  final String screen;

  const ShareJobButton({super.key, required this.message, required this.screen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      key: const Key('share-job'),
      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36), alignment: Alignment.centerLeft),
      onPressed: () =>
          shareViaWhatsApp(context, ref, message, flow: 'caregiver', screen: screen, action: 'share_job_whatsapp'),
      icon: const Icon(Icons.share, size: 16),
      label: const Text('Share this job on WhatsApp'),
    );
  }
}
