import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../app_versions/data/app_versions_repository.dart';

/// "Who must update": Everyone, or only the chosen categories (patients, caregivers, hospitals,
/// rehabs, clinics, agencies) and/or specific accounts. A controlled widget: the caller owns the
/// state and gets every change through the callbacks.
class AppVersionAudienceEditor extends StatelessWidget {
  final bool everyone;
  final Set<String> categories;
  final List<AudienceAccount> accounts;
  final ValueChanged<bool> onEveryoneChanged;
  final void Function(String category, bool selected) onCategoryToggled;
  final VoidCallback onAddAccount;
  final void Function(AudienceAccount account) onRemoveAccount;

  const AppVersionAudienceEditor({
    super.key,
    required this.everyone,
    required this.categories,
    required this.accounts,
    required this.onEveryoneChanged,
    required this.onCategoryToggled,
    required this.onAddAccount,
    required this.onRemoveAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Who must update', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<bool>(
          key: const Key('audience-mode'),
          segments: const [
            ButtonSegment(value: true, label: Text('Everyone')),
            ButtonSegment(value: false, label: Text('Selected only')),
          ],
          selected: {everyone},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onEveryoneChanged(s.first),
        ),
        if (!everyone) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text('Categories', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final c in AppVersionAudienceCategory.all)
                FilterChip(
                  key: Key('audience-category-$c'),
                  label: Text(AppVersionAudienceCategory.displayNames[c]!),
                  selected: categories.contains(c),
                  onSelected: (v) => onCategoryToggled(c, v),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Specific accounts', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final a in accounts)
                InputChip(
                  key: Key('audience-account-${a.userId}'),
                  label: Text('${a.chipLabel} (${a.kindLabel})'),
                  onDeleted: () => onRemoveAccount(a),
                ),
              ActionChip(
                key: const Key('audience-add-account'),
                avatar: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('Add account'),
                onPressed: onAddAccount,
              ),
            ],
          ),
          if (categories.isEmpty && accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Pick at least one category or account, or choose Everyone.',
                key: Key('audience-empty-hint'),
                style: TextStyle(color: AppColors.error),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Applies to the chosen categories and the chosen accounts together. Someone who is not signed in '
              'is checked as soon as they sign in.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
            ),
          ),
        ],
      ],
    );
  }
}

/// A search dialog over caregiver / patient / organisation accounts. Returns the chosen account, or
/// null when closed. [alreadyChosen] accounts are shown as taken.
Future<AudienceAccount?> showAccountPickerDialog(BuildContext context, {required Set<String> alreadyChosen}) {
  return showDialog<AudienceAccount>(
    context: context,
    builder: (_) => _AccountPickerDialog(alreadyChosen: alreadyChosen),
  );
}

class _AccountPickerDialog extends ConsumerStatefulWidget {
  final Set<String> alreadyChosen;

  const _AccountPickerDialog({required this.alreadyChosen});

  @override
  ConsumerState<_AccountPickerDialog> createState() => _AccountPickerDialogState();
}

class _AccountPickerDialogState extends ConsumerState<_AccountPickerDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<AudienceAccount> _results = [];
  bool _searching = false;
  String? _error;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    _lastQuery = query;
    if (query.length < 2) {
      setState(() {
        _results = [];
        _error = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ref.read(appVersionsRepositoryProvider).searchAccounts(query);
      if (!mounted || query != _lastQuery) return;
      setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted && query == _lastQuery) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an account'),
      content: SizedBox(
        width: context.dialogWidth(440),
        height: 380,
        child: Column(
          children: [
            TextField(
              key: const Key('account-picker-search'),
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (v) => _search(v.trim()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Name, phone, NUR-/PAT-/ORG- id or organisation',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_searching) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _lastQuery.length < 2 ? 'Type at least 2 characters.' : (_searching ? '' : 'No accounts found.'),
                        key: const Key('account-picker-empty'),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final a in _results)
                          ListTile(
                            key: Key('account-result-${a.userId}'),
                            dense: true,
                            enabled: !widget.alreadyChosen.contains(a.userId),
                            title: Text(a.chipLabel),
                            subtitle: Text('${a.kindLabel} · ${a.phone}'),
                            trailing: widget.alreadyChosen.contains(a.userId) ? const Text('Added') : null,
                            onTap: () => Navigator.of(context).pop(a),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
