import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';

/// Five stars showing [rating] (1-5), read-only.
class StarsRow extends StatelessWidget {
  final int rating;
  final double size;

  const StarsRow({super.key, required this.rating, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star : Icons.star_border, size: size, color: Colors.amber.shade700),
      ],
    );
  }
}

/// Overall feedback for one engagement, as a small block: what you wrote (or a
/// "Leave feedback" button once the work has started) and what the other side
/// wrote about you. Hidden entirely until there is something to show.
class FeedbackSection extends StatelessWidget {
  /// "caregiver" or "family" — who the feedback is about, for the wording.
  final String aboutLabel;
  final FeedbackModel? mine;
  final FeedbackModel? received;
  /// The work has started (the button is shown); the server enforces it anyway.
  final bool eligible;
  final VoidCallback? onLeave;
  /// When given, "Your feedback" gets an Edit button (patients/families can change theirs).
  final VoidCallback? onEdit;

  /// Wording of the write button and of the written feedback's heading (defaults suit the patient app).
  final String? leaveLabel;
  final String mineTitle;

  const FeedbackSection({
    super.key,
    this.leaveLabel,
    this.mineTitle = 'Your feedback',
    required this.aboutLabel,
    required this.mine,
    required this.received,
    required this.eligible,
    this.onLeave,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (mine == null && received == null && !eligible) return const SizedBox.shrink();
    return Container(
      key: const Key('feedback-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mine != null)
            _FeedbackBlock(keyName: 'feedback-mine', title: mineTitle, feedback: mine!, onEdit: onEdit)
          else if (eligible)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('leave-feedback'),
                onPressed: onLeave,
                icon: const Icon(Icons.star_outline, size: 18),
                label: Text(leaveLabel ?? 'Rate this $aboutLabel'),
              ),
            ),
          if (received != null) ...[
            if (mine != null || eligible) const SizedBox(height: AppSpacing.sm),
            // Stars only: the other side's written comment is private to admin, so it is never rendered here
            // (the server no longer sends it either).
            _FeedbackBlock(keyName: 'feedback-received', title: 'Feedback about you', feedback: received!, showComment: false),
          ],
        ],
      ),
    );
  }
}

class _FeedbackBlock extends StatelessWidget {
  final String keyName;
  final String title;
  final FeedbackModel feedback;
  final VoidCallback? onEdit;
  final bool showComment;

  const _FeedbackBlock({required this.keyName, required this.title, required this.feedback, this.onEdit, this.showComment = true});

  @override
  Widget build(BuildContext context) {
    final comment = feedback.comment;
    return Column(
      key: Key(keyName),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.small))),
            if (onEdit != null)
              TextButton.icon(
                key: const Key('edit-feedback'),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: 2),
        StarsRow(rating: feedback.rating),
        if (showComment && comment != null && comment.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(comment, key: Key('$keyName-comment')),
        ],
      ],
    );
  }
}

/// The "rate" bottom sheet: tap 1-5 stars, optionally write a short comment, send.
/// A bottom sheet (not a centred dialog) so the keyboard never covers the field or
/// the Send button. Returns true once the feedback was saved.
Future<bool> showFeedbackSheet(
  BuildContext context, {
  required String title,
  required Future<void> Function(int rating, String? comment) onSubmit,
  /// Opens with this feedback filled in and says it can be changed again (patients/families).
  FeedbackModel? existing,
  /// True where the sender may change it afterwards (patients/families); false when it is final (caregivers).
  bool canChangeLater = false,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _FeedbackSheet(title: title, onSubmit: onSubmit, existing: existing, canChangeLater: canChangeLater),
  );
  return saved ?? false;
}

class _FeedbackSheet extends StatefulWidget {
  final String title;
  final Future<void> Function(int rating, String? comment) onSubmit;
  final FeedbackModel? existing;
  final bool canChangeLater;

  const _FeedbackSheet({required this.title, required this.onSubmit, this.existing, this.canChangeLater = false});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.existing?.comment ?? '');
  late int _rating = widget.existing?.rating ?? 0;
  bool _saving = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _submitted = true);
    if (_rating == 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_rating, cleanFeedbackComment(_controller.text));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the whole sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: AppTypography.heading, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.existing != null
                    ? 'Change your stars or comment and save. They will see the new version.'
                    : 'Your feedback is about the whole time you worked together. It is shared only with them and the VitaCasa team. ${widget.canChangeLater ? 'You can change it later.' : 'It cannot be changed after you send it.'}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      key: Key('feedback-star-$i'),
                      tooltip: '$i star${i == 1 ? '' : 's'}',
                      iconSize: 38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: _saving ? null : () => setState(() => _rating = i),
                      icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: Colors.amber.shade700),
                    ),
                ],
              ),
              if (_submitted && _rating == 0)
                const Text('Please tap the stars to rate.',
                    key: Key('feedback-stars-error'), style: TextStyle(color: AppColors.error)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('feedback-comment'),
                controller: _controller,
                enabled: !_saving,
                maxLength: Validation.feedbackCommentMaxLength,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  hintText: 'A few words about your experience',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_error!, key: const Key('feedback-error'), style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton(
                    key: const Key('feedback-cancel'),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    key: const Key('feedback-submit'),
                    onPressed: _saving ? null : _send,
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(widget.existing != null ? 'Save changes' : 'Send feedback'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
