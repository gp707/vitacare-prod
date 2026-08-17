import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Shown once a caregiver has been accepted onto a job (MyJobs tab) — lets
/// them reach out to whoever posted it, by phone call or WhatsApp. Only
/// ever rendered when GET /caregiver/jobs/assigned returns a job_poster —
/// this contact info isn't shared before an actual accepted engagement.
class JobPosterContactCard extends StatelessWidget {
  final JobPosterModel poster;

  /// Injectable for widget tests — defaults to the real url_launcher call.
  final Future<bool> Function(Uri uri)? launcher;

  const JobPosterContactCard({super.key, required this.poster, this.launcher});

  Future<void> _open(BuildContext context, Uri uri, String failureMessage) async {
    bool launched;
    try {
      launched = launcher != null
          ? await launcher!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = poster.phone.replaceAll(RegExp(r'[^0-9]'), '');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Posted by',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(poster.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(poster.phone, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(
                    context,
                    Uri(scheme: 'tel', path: poster.phone),
                    'Could not open the dialer. Call ${poster.phone} directly.',
                  ),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(
                    context,
                    Uri.parse('https://wa.me/$digits'),
                    'Could not open WhatsApp. Message ${poster.phone} directly.',
                  ),
                  icon: const Icon(Icons.chat, size: 18, color: Color(0xFF25D366)),
                  label: const Text('WhatsApp'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
