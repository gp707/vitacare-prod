import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/app/rate_card_button.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/rate_card/rate_card_repository.dart';

final _dailyCard = RateCardModel(
  frequencyOfCare: FrequencyOfCare.daily,
  title: 'Salary Guidelines — Daily',
  columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
  rowLabels: ['Care'],
  cells: [
    ['867 per day', '933 per day', 'Caregivers are not suggested'],
  ],
);

final _monthlyCard = RateCardModel(
  frequencyOfCare: FrequencyOfCare.monthly,
  title: 'Salary Guidelines — Monthly',
  columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
  rowLabels: ['Care'],
  cells: [
    ['26000 pm', '28000 pm', 'Caregivers are not suggested'],
  ],
);

class _FakeRateCardRepository extends RateCardRepository {
  final List<RateCardModel>? result;
  final Object? error;

  _FakeRateCardRepository({this.result, this.error}) : super(Dio());

  @override
  Future<List<RateCardModel>> get() async {
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
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));

    expect(find.text('Rate Card'), findsOneWidget);
    expect(find.byIcon(Icons.currency_rupee), findsOneWidget);
  });

  testWidgets('tapping the button opens a dialog showing both the daily and monthly cards', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));

    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();

    expect(find.text('Salary Guidelines — Daily'), findsOneWidget);
    expect(find.text('Salary Guidelines — Monthly'), findsOneWidget);
    expect(find.text('Companion care'), findsNWidgets(2));
    expect(find.text('Care'), findsNWidgets(2));
    expect(find.text('867 per day'), findsOneWidget);
    expect(find.text('26000 pm'), findsOneWidget);
    expect(find.text('Caregivers are not suggested'), findsNWidgets(2));
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(tester, _FakeRateCardRepository(error: Exception('network down')));

    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load salary guidance'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));

    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();
    expect(find.text('Salary Guidelines — Daily'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Salary Guidelines — Daily'), findsNothing);
  });
}
