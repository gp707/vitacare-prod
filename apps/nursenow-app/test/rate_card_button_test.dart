import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/app/rate_card_button.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/rate_card/rate_card_repository.dart';

final _rateCard = RateCardModel(
  title: 'Salary Guidelines (12 hrs/24 hrs duty)',
  columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
  rowLabels: ['Caregivers', 'Nursing students', 'Nurses'],
  cells: [
    ['26000 pm/867 per day', '28000 pm/933 per day', 'Caregivers are not suggested'],
    ['28000 pm/933 per day', '30000 pm/1000 per day', '32000 pm/1067 per day'],
    ['30000 pm/1000 per day', '32000 pm/1067 per day', '35000-42000 pm'],
  ],
);

class _FakeRateCardRepository extends RateCardRepository {
  final RateCardModel? result;
  final Object? error;

  _FakeRateCardRepository({this.result, this.error}) : super(Dio());

  @override
  Future<RateCardModel> get() async {
    if (error != null) throw error!;
    return result!;
  }
}

Future<void> _pump(WidgetTester tester, RateCardRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [rateCardRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [RateCardButton()])),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a visible "Rate Card" label, not just a bare icon', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: _rateCard));

    expect(find.text('Rate Card'), findsOneWidget);
    expect(find.byIcon(Icons.currency_rupee), findsOneWidget);
  });

  testWidgets('tapping the button opens a dialog showing the title, labels, and cells', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: _rateCard));

    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();

    expect(find.text('Salary Guidelines (12 hrs/24 hrs duty)'), findsOneWidget);
    expect(find.text('Companion care'), findsOneWidget);
    expect(find.text('Caregivers'), findsOneWidget);
    expect(find.text('26000 pm/867 per day'), findsOneWidget);
    expect(find.text('Caregivers are not suggested'), findsOneWidget);
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(tester, _FakeRateCardRepository(error: Exception('network down')));

    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load salary guidance'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: _rateCard));

    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();
    expect(find.text('Salary Guidelines (12 hrs/24 hrs duty)'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Salary Guidelines (12 hrs/24 hrs duty)'), findsNothing);
  });
}
