import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/network/api_exception.dart';
import '../core/providers.dart';

/// "Delete My Account" on the Profile screen — irreversible, so this
/// re-collects the PIN as a re-auth step (same convention as a real
/// password re-entry before a destructive action) before calling the
/// backend, which anonymizes and deactivates the account rather than the
/// caller handling any cleanup itself. A wrong PIN (AUTH_008) is shown
/// inline and the dialog stays open for another attempt, same pattern as
/// [showForgotPinDialog]. Returns true if the account was actually
/// deleted — the caller (ProfileViewScreen) is responsible for logging
/// out and navigating away, this dialog never does that itself.
/// Duplicated in lib/patient_hospital/app/delete_account_dialog.dart —
/// same precedent as RateCardButton/WhatsAppHelpButton/ForgotPinDialog
/// (CLAUDE.md).
Future<bool> showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
  final codeController = TextEditingController();
  String? errorMessage;
  bool submitting = false;

  final deleted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final code = codeController.text.trim();
          if (code.length != 4) {
            setState(() => errorMessage = 'Enter your 4-digit PIN');
            return;
          }
          setState(() {
            submitting = true;
            errorMessage = null;
          });
          try {
            await ref.read(profileRepositoryProvider).deleteAccount(code);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          } on ApiException catch (e) {
            setState(() {
              errorMessage = e.message;
              submitting = false;
            });
          }
        }

        return AlertDialog(
          title: const Text('Delete My Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your account, profile, and documents. '
                'This cannot be undone. Enter your PIN to confirm.',
                style: TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: codeController,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Current 4-digit PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(errorMessage!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: submitting ? null : submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Delete Forever'),
            ),
          ],
        );
      },
    ),
  );

  return deleted ?? false;
}
