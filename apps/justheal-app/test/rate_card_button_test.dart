import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/patient_hospital/app/rate_card_button.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/rate_card/rate_card_repository.dart';

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
// The dialog's "Applicable Only For Home Care Jobs" notice blinks forever, so
// pumpAndSettle (which waits for animations to end) would never return —
// bounded pumps instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

  testWidgets('shows a visible "Rate Card" label, not just a bare icon', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));

    expect(find.text('Rate Card'), findsOneWidget);
    expect(find.byIcon(Icons.currency_rupee), findsOneWidget);
  });

  testWidgets('tapping the button opens a dialog showing both the daily and monthly cards', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));

    await tester.tap(find.text('Rate Card'));
    await _settle(tester);

    expect(find.text('Salary Guidelines — Daily'), findsOneWidget);
    expect(find.text('Salary Guidelines — Monthly'), findsOneWidget);
    expect(find.text('Companion care'), findsNWidgets(2));
    // No row-label column any more — the single "Care" row has no leading
    // label, so "Care" is no longer rendered here.
    expect(find.text('867 per day'), findsOneWidget);
    expect(find.text('26000 pm'), findsOneWidget);
    expect(find.text('Caregivers are not suggested'), findsNWidgets(2));
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(tester, _FakeRateCardRepository(error: Exception('network down')));

    await tester.tap(find.text('Rate Card'));
    await _settle(tester);

    expect(find.textContaining('Could not load salary guidance'), findsOneWidget);
  });

  testWidgets(
      'a long admin-entered title (e.g. "...(12 hrs/24 hrs duty) — Monthly") wraps instead of '
      'clipping off the dialog on a narrow screen — the frequency word at the end is what actually '
      'tells the two tables apart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longTitleCard = RateCardModel(
      frequencyOfCare: FrequencyOfCare.monthly,
      title: 'Salary Guidelines (12 hrs/24 hrs duty) — Monthly',
      columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
      rowLabels: ['Care'],
      cells: [
        ['26,000 - 30,000', '28,000 - 32000', '32,000 - 42,000'],
      ],
    );
    await _pump(tester, _FakeRateCardRepository(result: [longTitleCard]));

    await tester.tap(find.text('Rate Card'));
    await _settle(tester);

    // No RenderFlex overflow (the title used to clip off the dialog's
    // right edge, including the "— Monthly" suffix — the one word that
    // distinguishes this table from the daily one).
    expect(tester.takeException(), isNull);
    expect(find.text('Salary Guidelines (12 hrs/24 hrs duty) — Monthly'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));

    await tester.tap(find.text('Rate Card'));
    await _settle(tester);
    expect(find.text('Salary Guidelines — Daily'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await _settle(tester);
    expect(find.text('Salary Guidelines — Daily'), findsNothing);
  });

  testWidgets('the Home Care notice is red text on a yellow highlight and blinks', (tester) async {
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));
    await tester.tap(find.text('Rate Card'));
    await _settle(tester);

    final notice = find.text('Applicable Only For Home Care Jobs');
    expect(notice, findsOneWidget);
    expect(tester.widget<Text>(notice).style!.color, AppColors.error);
    final box = tester.widget<Container>(find.ancestor(of: notice, matching: find.byType(Container)).first);
    expect((box.decoration! as BoxDecoration).color, Colors.yellow);

    double opacity() => tester.widget<FadeTransition>(find.ancestor(of: notice, matching: find.byType(FadeTransition)).first).opacity.value;
    final seen = <double>{};
    for (var i = 0; i < 8; i++) {
      seen.add(double.parse(opacity().toStringAsFixed(2)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(seen.length, greaterThan(2), reason: 'opacity changes over time (blinks)');
    expect(seen.reduce((a, b) => a < b ? a : b), lessThan(0.6));
  });

  testWidgets('the notice stays steady when the phone\'s remove-animations setting is on', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, _FakeRateCardRepository(result: [_dailyCard, _monthlyCard]));
    await tester.tap(find.text('Rate Card'));
    await tester.pumpAndSettle();

    final notice = find.text('Applicable Only For Home Care Jobs');
    expect(notice, findsOneWidget);
    final fade = tester.widget<FadeTransition>(find.ancestor(of: notice, matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, 1.0);
  });
}
