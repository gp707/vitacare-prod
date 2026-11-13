import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../core/network/api_exception.dart';

/// Quick view / add / edit of an admin-only internal note, opened from a
/// "Notes" button right on a list row. Where the note lives is the caller's
/// business ([load]/[save]) — this only handles the dialog.
Future<void> showAdminNotesDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required Future<String?> Function() load,
  required Future<void> Function(String notes) save,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AdminNotesDialog(
      title: title,
      hint: hint,
      load: load,
      save: save,
    ),
  );
}

class _AdminNotesDialog extends StatefulWidget {
  final String title;
  final String hint;
  final Future<String?> Function() load;
  final Future<void> Function(String notes) save;

  const _AdminNotesDialog({
    required this.title,
    required this.hint,
    required this.load,
    required this.save,
  });

  @override
  State<_AdminNotesDialog> createState() => _AdminNotesDialogState();
}

class _AdminNotesDialogState extends State<_AdminNotesDialog> {
  final _controller = TextEditingController();
  String _saved = '';
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await widget.load();
      if (!mounted) return;
      setState(() {
        _saved = notes ?? '';
        _controller.text = _saved;
        _loading = false;
        // Nothing to read yet: go straight to typing.
        _editing = _saved.isEmpty;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final text = _controller.text.trim();
      await widget.save(text);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _controller.text = text;
        _editing = text.isEmpty;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: context.dialogWidth(420),
        child: _loading
            ? const Center(
                heightFactor: 2,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_editing)
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      minLines: 4,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        border: const OutlineInputBorder(),
                      ),
                    )
                  else
                    SelectableText(_saved),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (!_loading && _editing && _saved.isNotEmpty)
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                      _editing = false;
                      _controller.text = _saved;
                    }),
            child: const Text('Cancel'),
          ),
        if (!_loading && _editing)
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        if (!_loading && !_editing)
          ElevatedButton(
            onPressed: () => setState(() => _editing = true),
            child: const Text('Edit'),
          ),
      ],
    );
  }
}
