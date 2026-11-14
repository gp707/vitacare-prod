import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'confirm_action.dart';

/// Row width from which the notes panel sits in the row's right-hand column;
/// narrower rows stack it below the row's content instead.
const _sideBySideMinWidth = 900.0;
const _panelWidth = 400.0;

/// Puts [panel] in a right-hand column beside [main] on a wide row, or below
/// it on a narrow one.
class NotesSideLayout extends StatelessWidget {
  final Widget main;
  final Widget panel;
  const NotesSideLayout({super.key, required this.main, required this.panel});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= _sideBySideMinWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: main),
            const SizedBox(width: AppSpacing.md),
            SizedBox(width: _panelWidth, child: panel),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [main, const SizedBox(height: AppSpacing.sm), panel],
      );
    });
  }
}

/// Admin's internal note, viewable and editable right on a list row. Save asks
/// for confirmation first, like every other change that is written to disk.
class InlineNotesPanel extends StatefulWidget {
  /// Who the note is about, e.g. "this patient" — shown in the heading and in
  /// the confirmation so admin knows what a shared note covers.
  final String subject;
  final String? notes;
  final Future<void> Function(String notes) onSave;

  /// A smaller box without the heading, for a table cell.
  final bool compact;

  const InlineNotesPanel(
      {super.key,
      required this.subject,
      required this.notes,
      required this.onSave,
      this.compact = false});

  @override
  State<InlineNotesPanel> createState() => _InlineNotesPanelState();
}

class _InlineNotesPanelState extends State<InlineNotesPanel> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.notes ?? '');
  bool _saving = false;

  String get _saved => (widget.notes ?? '').trim();
  bool get _dirty => _controller.text.trim() != _saved;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(InlineNotesPanel old) {
    super.didUpdateWidget(old);
    // A refreshed list brings the saved note; never overwrite what admin is typing.
    if (old.notes != widget.notes && !_dirty)
      _controller.text = widget.notes ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final confirmed = await confirmAction(
      context,
      title: 'Save note?',
      message: 'This replaces the saved internal note about ${widget.subject}.',
      confirmLabel: 'Save note',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text.trim());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the note. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.compact)
          Row(children: [
            const Icon(Icons.sticky_note_2_outlined, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text('Internal note · ${widget.subject}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: AppTypography.small)),
            ),
          ]),
        if (!widget.compact) const SizedBox(height: AppSpacing.xs),
        TextField(
          key: const Key('inline-notes-field'),
          controller: _controller,
          enabled: !_saving,
          minLines: widget.compact ? 2 : 6,
          maxLines: widget.compact ? 5 : 12,
          style: const TextStyle(fontSize: AppTypography.small),
          decoration: const InputDecoration(
            hintText: 'Add a note (only admins see this)',
            isDense: true,
            border: OutlineInputBorder(),
            filled: true,
          ),
        ),
        if (_dirty || _saving)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('inline-notes-cancel'),
                  onPressed: _saving
                      ? null
                      : () => _controller.text = widget.notes ?? '',
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  key: const Key('inline-notes-save'),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
