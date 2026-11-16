import 'package:flutter/material.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

/// The most days that can be marked as leave in one go (the server's limit too).
const int maxLeaveDaysAtOnce = 31;

/// A small calendar where the patient taps each day the caregiver is on leave —
/// specific days, never a range, and the days need not be next to each other.
///
/// Returns the chosen days as YYYY-MM-DD (sorted), or null if cancelled.
/// Days before [firstDate] or after [lastDate] can't be chosen, and days in
/// [alreadyMarked] are shown as leave already (cancel those from the salary page).
Future<List<String>?> showLeaveDaysDialog(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  required DateTime initialMonth,
  List<String> alreadyMarked = const [],
  String? note,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _LeaveDaysDialog(
      firstDate: DateTime(firstDate.year, firstDate.month, firstDate.day),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
      initialMonth: initialMonth,
      alreadyMarked: alreadyMarked.toSet(),
      note: note,
    ),
  );
}

class _LeaveDaysDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;
  final Set<String> alreadyMarked;
  final String? note;

  const _LeaveDaysDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialMonth,
    required this.alreadyMarked,
    this.note,
  });

  @override
  State<_LeaveDaysDialog> createState() => _LeaveDaysDialogState();
}

class _LeaveDaysDialogState extends State<_LeaveDaysDialog> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdayInitials = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  late DateTime _month; // first day of the month being shown
  final Set<String> _selected = {};
  String? _hint;

  @override
  void initState() {
    super.initState();
    final start = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    final first = DateTime(widget.firstDate.year, widget.firstDate.month);
    final last = DateTime(widget.lastDate.year, widget.lastDate.month);
    _month = start.isBefore(first) ? first : (start.isAfter(last) ? last : start);
  }

  bool get _canGoBack => _month.isAfter(DateTime(widget.firstDate.year, widget.firstDate.month));
  bool get _canGoForward => _month.isBefore(DateTime(widget.lastDate.year, widget.lastDate.month));

  void _shiftMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  bool _inRange(DateTime day) => !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);

  void _toggle(String iso) {
    setState(() {
      if (_selected.contains(iso)) {
        _selected.remove(iso);
        _hint = null;
      } else if (_selected.length >= maxLeaveDaysAtOnce) {
        _hint = 'You can mark up to $maxLeaveDaysAtOnce days at a time.';
      } else {
        _selected.add(iso);
        _hint = null;
      }
    });
  }

  Widget _dayCell(int dayOfMonth) {
    final day = DateTime(_month.year, _month.month, dayOfMonth);
    final iso = toIsoDate(DateTime.utc(day.year, day.month, day.day));
    final marked = widget.alreadyMarked.contains(iso);
    final selectable = _inRange(day) && !marked;
    final selected = _selected.contains(iso);
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

    final Color? background = selected
        ? Colors.deepOrange.shade600
        : marked
            ? Colors.deepOrange.shade50
            : null;
    final Color textColor = selected
        ? Colors.white
        : marked
            ? Colors.deepOrange.shade800
            : (selectable ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.45));

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Tooltip(
        message: marked ? 'Already marked as leave' : '',
        child: InkWell(
          key: Key('leave-day-$iso'),
          customBorder: const CircleBorder(),
          onTap: selectable ? () => _toggle(iso) : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: isToday && !selected ? Border.all(color: AppColors.primary) : null,
            ),
            child: Text(
              '$dayOfMonth',
              style: TextStyle(
                color: textColor,
                fontWeight: selected || marked ? FontWeight.bold : FontWeight.normal,
                decoration: marked ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Weeks start on Sunday: DateTime.weekday is 1 (Mon) .. 7 (Sun).
    final leadingBlanks = DateTime(_month.year, _month.month).weekday % 7;
    final count = _selected.length;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select the leave days', style: TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              const Text(
                'Tap each day the caregiver is on leave.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.small),
              ),
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.note!,
                    key: const Key('leave-cycle-note'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypography.small),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  IconButton(
                    key: const Key('leave-prev-month'),
                    tooltip: 'Previous month',
                    onPressed: _canGoBack ? () => _shiftMonth(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_monthNames[_month.month - 1]} ${_month.year}',
                      key: const Key('leave-month-title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    key: const Key('leave-next-month'),
                    tooltip: 'Next month',
                    onPressed: _canGoForward ? () => _shiftMonth(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final initial in _weekdayInitials)
                    Expanded(
                      child: Center(
                        child: Text(initial, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
                  for (var d = 1; d <= daysInMonth; d++) _dayCell(d),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                count == 0 ? 'No days selected' : (count == 1 ? '1 day selected' : '$count days selected'),
                key: const Key('leave-selected-count'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_hint != null)
                Text(_hint!, key: const Key('leave-hint'), style: const TextStyle(color: AppColors.error, fontSize: AppTypography.small)),
              const SizedBox(height: AppSpacing.sm),
              // A Wrap, not a Row: on a narrow screen or with large text the buttons drop to
              // the next line instead of overflowing.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  FilledButton(
                    key: const Key('leave-confirm'),
                    onPressed: count == 0 ? null : () => Navigator.of(context).pop(_selected.toList()..sort()),
                    child: const Text('Mark leave'),
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
