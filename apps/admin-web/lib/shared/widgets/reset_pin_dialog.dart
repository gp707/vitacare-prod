import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Shared by CaregiverDetailScreen/IndividualDetailScreen/
/// OrganisationDetailScreen — admin types the account's new 4-digit login
/// PIN directly (no old-PIN check, same as self-service), rather than the
/// system generating one. Returns the new code, or null if cancelled.
Future<String?> showResetPinDialog(BuildContext context, {required String accountLabel}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final formKey = GlobalKey<FormState>();
      return AlertDialog(
        title: Text('Reset PIN — $accountLabel'),
        content: Form(
          key: formKey,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'New 4-digit PIN',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (controller.text.trim().length != 4) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter exactly 4 digits'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Reset PIN'),
          ),
        ],
      );
    },
  );
}
