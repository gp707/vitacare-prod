import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../core/network/api_exception.dart';
import '../core/providers.dart';

/// "Forgot PIN?" on the login screen — there's no OTP/email PIN reset, so
/// this creates a support ticket instead (CLAUDE.md's Support Tickets
/// section): admin verifies identity out of band, then resets the PIN
/// from the account's own admin-web detail screen. Duplicated in
/// lib/patient_hospital/app/forgot_pin_dialog.dart — same precedent as
/// RateCardButton/WhatsAppHelpButton (CLAUDE.md).
Future<void> showForgotPinDialog(
  BuildContext context,
  WidgetRef ref, {
  required String initialPhone,
}) async {
  final phoneController = TextEditingController(text: initialPhone);
  String? errorMessage;
  bool submitting = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final digitsOnly = phoneController.text.trim();
          if (!Validators.isValidPhone('+91$digitsOnly')) {
            setState(() => errorMessage = 'Enter a valid 10-digit mobile number');
            return;
          }
          setState(() {
            submitting = true;
            errorMessage = null;
          });
          try {
            final message = await ref.read(authRepositoryProvider).forgotPin('+91$digitsOnly');
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }
          } on ApiException catch (e) {
            setState(() {
              errorMessage = e.message;
              submitting = false;
            });
          }
        }

        return AlertDialog(
          title: const Text('Forgot PIN?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "We'll create a support ticket so our team can verify your identity and reset your PIN.",
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  prefixText: '+91 ',
                  labelText: 'Phone number',
                  border: OutlineInputBorder(),
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
              onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: submitting ? null : submit,
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create Ticket'),
            ),
          ],
        );
      },
    ),
  );
}
