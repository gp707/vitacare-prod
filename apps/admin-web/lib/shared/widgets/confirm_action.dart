import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// Asks the admin to confirm before something is saved or sent. Returns true
/// only on an explicit confirm; Cancel, Esc or a click outside all mean no.
/// [details] are short bullet lines (e.g. which fields are about to change).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  List<String> details = const [],
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: dialogContext.dialogWidth(420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (details.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final line in details)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('•  $line'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
