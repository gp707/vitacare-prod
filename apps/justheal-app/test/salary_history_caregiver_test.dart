import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/caregiver/core/network/api_exception.dart';
import 'package:nursenow_app/caregiver/features/jobs/widgets/salary_history.dart';

const _paid = SalaryCycleModel(
  cycleStart: '2026-11-18',
  cycleEnd: '2026-12-01',
  rate: 900,
  unit: 'daily',
  leaveDates: ['2026-11-24'],
  workedDays: 13,
  amount: 11700,
  status: 'paid',
  paidOn: '2026-12-02',
);
const _current = SalaryCycleModel(
  cycleStart: '2026-12-02',
  cycleEnd: '2026-12-15',
  rate: 1000,
  unit: 'daily',
  workedDays: 14,
  amount: 14000,
  status: 'current',
);

Future<void> _pump(WidgetTester tester, Future<List<SalaryCycleModel>> Function() load) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SalaryHistory(load: load)))),
    );

void main() {
  testWidgets('is closed and loads nothing until opened', (tester) async {
    var loads = 0;
    await _pump(tester, () async {
      loads++;
      return [_current, _paid];
    });
    expect(find.text('Salary history'), findsOneWidget);
    expect(find.byKey(const Key('cycle-2026-12-02')), findsNothing);
    expect(loads, 0);
  });

  testWidgets('opening it shows each cycle: dates, status, the old rate and leave of a paid cycle, and the new rate', (tester) async {
    await _pump(tester, () async => [_current, _paid]);
    await tester.tap(find.byKey(const Key('salary-history-toggle')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('cycle-status-2026-11-18'))).data, 'Paid on 2 Dec 2026');
    expect(tester.widget<Text>(find.byKey(const Key('cycle-calc-2026-11-18'))).data, '\u20b9900/day \u00d7 13 days = \u20b911,700');
    expect(tester.widget<Text>(find.byKey(const Key('cycle-leave-2026-11-18'))).data, startsWith('Leave (1):'));
    expect(tester.widget<Text>(find.byKey(const Key('cycle-status-2026-12-02'))).data, 'Current cycle');
    expect(tester.widget<Text>(find.byKey(const Key('cycle-calc-2026-12-02'))).data, '\u20b91,000/day \u00d7 14 days = \u20b914,000');
    // read-only for the caregiver
    expect(find.text('Mark as paid'), findsNothing);
  });

  testWidgets('says so when there are no cycles yet', (tester) async {
    await _pump(tester, () async => []);
    await tester.tap(find.byKey(const Key('salary-history-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salary-history-empty')), findsOneWidget);
  });

  testWidgets('shows a friendly error when it cannot load, and reloads when opened again', (tester) async {
    var calls = 0;
    await _pump(tester, () async {
      calls++;
      if (calls == 1) throw const ApiException(message: 'Could not reach the server', code: 'NETWORK');
      return [_paid];
    });
    await tester.tap(find.byKey(const Key('salary-history-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the server'), findsOneWidget);
    await tester.tap(find.byKey(const Key('salary-history-toggle'))); // close
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('salary-history-toggle'))); // open again
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-2026-11-18')), findsOneWidget);
    expect(find.text('Could not reach the server'), findsNothing);
  });
}
