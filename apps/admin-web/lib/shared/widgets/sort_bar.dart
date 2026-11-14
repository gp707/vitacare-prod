import 'package:flutter/material.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

class SortOption {
  final String key;
  final String label;
  const SortOption(this.key, this.label);
}

/// The sort after a column header (or the dropdown) picks [tappedKey]: picking
/// the active column flips its direction; a new column starts ascending, except
/// the registration date, which starts newest first.
(String, bool) nextSort({
  required String currentKey,
  required bool currentAscending,
  required String tappedKey,
}) {
  if (tappedKey == currentKey) return (currentKey, !currentAscending);
  return (tappedKey, tappedKey != 'created_at');
}

/// "Sort by [column] [direction]" — the list-sorting control for layouts
/// without clickable table headers (and a handy shortcut on wide ones).
class SortBar extends StatelessWidget {
  final List<SortOption> options;
  final String sortKey;
  final bool ascending;
  final void Function(String key, bool ascending) onChanged;

  const SortBar({
    super.key,
    required this.options,
    required this.sortKey,
    required this.ascending,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Sort by', style: TextStyle(fontSize: AppTypography.small)),
        const SizedBox(width: AppSpacing.sm),
        DropdownButton<String>(
          key: const Key('sort-bar-field'),
          value: sortKey,
          underline: const SizedBox.shrink(),
          items: [for (final o in options) DropdownMenuItem(value: o.key, child: Text(o.label))],
          // Picking a different column starts from that column's natural order.
          onChanged: (key) {
            if (key == null || key == sortKey) return;
            onChanged(key, key != 'created_at');
          },
        ),
        IconButton(
          key: const Key('sort-bar-direction'),
          tooltip: ascending ? 'Ascending — click for descending' : 'Descending — click for ascending',
          icon: Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
          onPressed: () => onChanged(sortKey, !ascending),
        ),
      ],
    );
  }
}
