import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nursenow_app/patient_hospital/features/individual/widgets/leave_days_dialog.dart';

/// Opens the dialog from a button and keeps what it returns.
class _Harness {
  List<String>? result;
  bool returned = false;
}

Future<_Harness> _open(
  WidgetTester tester, {
  List<String> alreadyMarked = const [],
  DateTime? first,
  DateTime? last,
  DateTime? month,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                harness.result = await showLeaveDaysDialog(
                  context,
                  firstDate: first ?? DateTime(2026, 11, 17),
                  lastDate: last ?? DateTime(2027, 11, 17),
                  initialMonth: month ?? DateTime(2026, 11, 20),
                  alreadyMarked: alreadyMarked,
                );
                harness.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

Finder _day(String iso) => find.byKey(Key('leave-day-$iso'));

Future<void> _tap(WidgetTester tester, String iso) async {
  await tester.tap(_day(iso));
  await tester.pump();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('leave-next-month')));
  await tester.pump();
}

void main() {
  testWidgets('opens on the given month with a clear title and instruction', (tester) async {
    await _open(tester);
    expect(find.text('Select the leave days'), findsOneWidget);
    expect(find.textContaining('Tap each day the caregiver is on leave'), findsOneWidget);
    expect(find.byKey(const Key('leave-month-title')), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('No days selected'), findsOneWidget);
  });

  testWidgets('there is no range: two days that are not next to each other are exactly what is returned', (tester) async {
    final harness = await _open(tester);
    await _tap(tester, '2026-11-18');
    await _tap(tester, '2026-11-25');
    expect(find.text('2 days selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave-confirm')));
    await tester.pumpAndSettle();
    expect(harness.result, ['2026-11-18', '2026-11-25']);
  });

  testWidgets('the days between two chosen days are NOT included', (tester) async {
    final harness = await _open(tester);
    await _tap(tester, '2026-11-18');
    await _tap(tester, '2026-11-22');
    await tester.tap(find.byKey(const Key('leave-confirm')));
    await tester.pumpAndSettle();
    expect(harness.result, hasLength(2));
    expect(harness.result, isNot(contains('2026-11-19')));
  });

  testWidgets('tapping a chosen day again un-chooses it', (tester) async {
    await _open(tester);
    await _tap(tester, '2026-11-18');
    expect(find.text('1 day selected'), findsOneWidget);
    await _tap(tester, '2026-11-18');
    expect(find.text('No days selected'), findsOneWidget);
  });

  testWidgets('Mark leave stays disabled until at least one day is chosen', (tester) async {
    await _open(tester);
    FilledButton button() => tester.widget<FilledButton>(find.byKey(const Key('leave-confirm')));
    expect(button().onPressed, isNull);
    await _tap(tester, '2026-11-20');
    expect(button().onPressed, isNotNull);
  });

  testWidgets('Cancel returns nothing', (tester) async {
    final harness = await _open(tester);
    await _tap(tester, '2026-11-20');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.returned, isTrue);
    expect(harness.result, isNull);
  });

  testWidgets('days before the first allowed day cannot be chosen', (tester) async {
    await _open(tester);
    await _tap(tester, '2026-11-16');
    expect(find.text('No days selected'), findsOneWidget);
    await _tap(tester, '2026-11-17');
    expect(find.text('1 day selected'), findsOneWidget);
  });

  testWidgets('days already marked as leave are shown but cannot be chosen again', (tester) async {
    await _open(tester, alreadyMarked: ['2026-11-24']);
    await _tap(tester, '2026-11-24');
    expect(find.text('No days selected'), findsOneWidget);
  });

  testWidgets('the month can be changed, and days chosen in different months are all kept', (tester) async {
    final harness = await _open(tester);
    await _tap(tester, '2026-11-30');
    await _next(tester);
    expect(find.text('December 2026'), findsOneWidget);
    await _tap(tester, '2026-12-02');
    expect(find.text('2 days selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('leave-confirm')));
    await tester.pumpAndSettle();
    expect(harness.result, ['2026-11-30', '2026-12-02']);
  });

  testWidgets('cannot go before the first month or after the last month', (tester) async {
    await _open(tester);
    IconButton prev() => tester.widget<IconButton>(find.byKey(const Key('leave-prev-month')));
    IconButton next() => tester.widget<IconButton>(find.byKey(const Key('leave-next-month')));
    expect(prev().onPressed, isNull); // November 2026 is the first month
    expect(next().onPressed, isNotNull);
    for (var i = 0; i < 12; i++) {
      await _next(tester);
    }
    expect(find.text('November 2027'), findsOneWidget);
    expect(next().onPressed, isNull);
    expect(prev().onPressed, isNotNull);
  });

  testWidgets('days sit under the right weekday (weeks start on Sunday)', (tester) async {
    await _open(tester);
    // 1 Nov 2026 is a Sunday: 1 and 8 line up.
    expect(tester.getTopLeft(_day('2026-11-01')).dx, tester.getTopLeft(_day('2026-11-08')).dx);
    await _next(tester);
    // 1 Dec 2026 is a Tuesday, so it lines up with 8 Dec but not with 7 Dec (a Monday).
    expect(tester.getTopLeft(_day('2026-12-01')).dx, tester.getTopLeft(_day('2026-12-08')).dx);
    expect(tester.getTopLeft(_day('2026-12-01')).dx, isNot(tester.getTopLeft(_day('2026-12-07')).dx));
  });

  testWidgets('at most 31 days can be chosen at once, with a clear message', (tester) async {
    await _open(tester, first: DateTime(2026, 11, 1), last: DateTime(2027, 11, 1), month: DateTime(2026, 11, 1));
    for (var d = 1; d <= 30; d++) {
      await _tap(tester, '2026-11-${d.toString().padLeft(2, '0')}');
    }
    await _next(tester);
    await _tap(tester, '2026-12-01');
    expect(find.text('31 days selected'), findsOneWidget);
    await _tap(tester, '2026-12-02');
    expect(find.text('31 days selected'), findsOneWidget);
    expect(find.byKey(const Key('leave-hint')), findsOneWidget);
    expect(find.text('You can mark up to 31 days at a time.'), findsOneWidget);
  });

  testWidgets('opens on the start month when the job starts after the requested month', (tester) async {
    await _open(tester, first: DateTime(2027, 1, 5), last: DateTime(2028, 1, 5), month: DateTime(2026, 11, 20));
    expect(find.text('January 2027'), findsOneWidget);
  });
}
