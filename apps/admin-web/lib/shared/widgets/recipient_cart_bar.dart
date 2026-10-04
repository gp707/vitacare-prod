import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../state/recipient_selection_cart.dart';
import '../../features/push_notifications/widgets/compose_notification_dialog.dart';

/// Shown at the bottom of the Caregivers/Patients-Family/Rehab-Hospitals
/// list screens whenever the recipient selection cart is non-empty — the
/// one entry point into composing a bulk push notification, reachable
/// from any of those three screens since the cart itself is shared state.
/// Collapses to nothing (not even a SizedBox.shrink placeholder height)
/// when the cart is empty, so it never otherwise affects layout.
class RecipientCartBar extends ConsumerWidget {
  const RecipientCartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(recipientSelectionCartProvider);
    if (cart.isEmpty) return const SizedBox.shrink();

    final counts = <String, int>{};
    for (final recipient in cart.values) {
      counts[recipient.role] = (counts[recipient.role] ?? 0) + 1;
    }
    final summary = counts.entries.map((e) => '${e.value} ${_roleLabel(e.key, e.value)}').join(', ');

    return Material(
      elevation: 8,
      color: AppColors.primaryDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.campaign_outlined, color: Colors.white),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('$summary selected', style: const TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => ref.read(recipientSelectionCartProvider.notifier).clear(),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Clear'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ComposeNotificationDialog(),
              ),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Notify Selected'),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role, int count) {
    switch (role) {
      case 'caregiver':
        return count == 1 ? 'caregiver' : 'caregivers';
      case 'individual':
        return count == 1 ? 'patient' : 'patients';
      case 'organisation':
        return count == 1 ? 'organisation' : 'organisations';
      default:
        return role;
    }
  }
}
