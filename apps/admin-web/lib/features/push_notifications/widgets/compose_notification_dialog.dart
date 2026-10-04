import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/state/recipient_selection_cart.dart';

/// Composes and sends (or schedules) one push notification to everyone
/// currently in the recipient selection cart — opened from
/// RecipientCartBar on any of the Caregivers/Patients-Family/Rehab-
/// Hospitals list screens. On success, clears the cart (the notification
/// has been created server-side; starting a new one should start from an
/// empty selection, not accidentally resend to the same group).
class ComposeNotificationDialog extends ConsumerStatefulWidget {
  const ComposeNotificationDialog({super.key});

  @override
  ConsumerState<ComposeNotificationDialog> createState() => _ComposeNotificationDialogState();
}

class _ComposeNotificationDialogState extends ConsumerState<ComposeNotificationDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _scheduleForLater = false;
  DateTime? _scheduledDateTime;
  bool _sending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDateTime ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledDateTime ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _scheduledDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  bool get _canSend {
    if (_sending) return false;
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) return false;
    if (_scheduleForLater && _scheduledDateTime == null) return false;
    if (_scheduleForLater && _scheduledDateTime != null && _scheduledDateTime!.isBefore(DateTime.now())) {
      return false;
    }
    return true;
  }

  Future<void> _send() async {
    final recipients = ref.read(recipientSelectionCartProvider).values.toList();
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      final notification = await ref.read(adminPushNotificationsRepositoryProvider).create(
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            scheduledAt: _scheduleForLater ? _scheduledDateTime : null,
            recipientUserIds: recipients.map((r) => r.userId).toList(),
          );
      if (!mounted) return;
      ref.read(recipientSelectionCartProvider.notifier).clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notification.status == 'sent'
                ? 'Notification sent to ${notification.recipientCount} recipient(s)'
                : notification.status == 'failed'
                    ? 'Notification could not be delivered — see Push Notifications history'
                    : 'Notification scheduled for ${notification.scheduledAt}',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipients = ref.watch(recipientSelectionCartProvider).values.toList();
    final counts = <String, int>{};
    for (final r in recipients) {
      counts[r.role] = (counts[r.role] ?? 0) + 1;
    }

    return AlertDialog(
      title: const Text('Notify Selected Recipients'),
      content: SizedBox(
        width: context.dialogWidth(480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                children: counts.entries
                    .map((e) => Chip(label: Text('${e.value} ${_roleLabel(e.key, e.value)}')))
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _titleController,
                maxLength: Validation.pushNotificationTitleMaxLength,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _bodyController,
                maxLength: Validation.pushNotificationBodyMaxLength,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Send now')),
                  ButtonSegment(value: true, label: Text('Schedule for later')),
                ],
                selected: {_scheduleForLater},
                onSelectionChanged: (selection) => setState(() => _scheduleForLater = selection.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_scheduleForLater)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.lg),
                  child: OutlinedButton.icon(
                    onPressed: _pickDateTime,
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      _scheduledDateTime == null
                          ? 'Pick date & time'
                          : _formatDateTime(_scheduledDateTime!),
                    ),
                  ),
                ),
              if (_scheduleForLater &&
                  _scheduledDateTime != null &&
                  _scheduledDateTime!.isBefore(DateTime.now()))
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text('Pick a time in the future', style: TextStyle(color: AppColors.error)),
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _canSend ? _send : null,
          icon: _sending
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send, size: 16),
          label: Text(_scheduleForLater ? 'Schedule' : 'Send Now'),
        ),
      ],
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

  String _formatDateTime(DateTime dt) {
    final date = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
