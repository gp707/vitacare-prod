import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../data/admin_feedback_repository.dart';

/// Admin corrects one feedback: change the star rating and/or the comment (clearing the box removes
/// the comment). [onSave] performs the call; an [ApiException] it throws is shown inside the dialog,
/// which stays open. Returns true only when it was saved.
Future<bool> showEditFeedbackDialog(
  BuildContext context, {
  required AdminFeedbackItem item,
  required Future<void> Function(int rating, String? comment) onSave,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _EditFeedbackDialog(item: item, onSave: onSave),
  );
  return saved ?? false;
}

class _EditFeedbackDialog extends StatefulWidget {
  final AdminFeedbackItem item;
  final Future<void> Function(int rating, String? comment) onSave;

  const _EditFeedbackDialog({required this.item, required this.onSave});

  @override
  State<_EditFeedbackDialog> createState() => _EditFeedbackDialogState();
}

class _EditFeedbackDialogState extends State<_EditFeedbackDialog> {
  late int _rating = widget.item.rating;
  late final TextEditingController _comment = TextEditingController(text: widget.item.comment ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final text = _comment.text.trim();
      await widget.onSave(_rating, text.isEmpty ? null : text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final who = item.byPatient ? '${item.patientLabel} about ${item.caregiverLabel}' : '${item.caregiverLabel} about ${item.patientLabel}';
    return AlertDialog(
      title: const Text('Edit feedback'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(who, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    key: Key('edit-feedback-star-$i'),
                    onPressed: _saving ? null : () => setState(() => _rating = i),
                    icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: Colors.amber.shade700, size: 30),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('edit-feedback-comment'),
              controller: _comment,
              enabled: !_saving,
              maxLines: 4,
              maxLength: Validation.feedbackCommentMaxLength,
              decoration: const InputDecoration(labelText: 'Comment (leave empty for none)', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('edit-feedback-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
