import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/rate_card/data/rate_card_repository.dart';
import 'package:admin_web/features/rate_card/screens/rate_card_screen.dart';

RateCardModel _rateCard({required String frequency, required String title}) {
  return RateCardModel(
    frequencyOfCare: frequency,
    title: title,
    columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
    rowLabels: ['Care'],
    cells: [
      ['26000 pm', '28000 pm', 'Not suggested'],
    ],
  );
}

class _FakeRateCardRepository extends RateCardRepository {
  Map<String, RateCardModel> current;
  Map<String, String?> updatedByName;
  Map<String, RateCardModel> savedRateCards = {};
  bool throwOnUpdate;

  _FakeRateCardRepository(this.current, {Map<String, String?>? updatedByName, this.throwOnUpdate = false})
      : updatedByName = updatedByName ?? {},
        super(Dio());

  @override
  Future<List<RateCardWithUpdater>> get() async => [
        for (final frequency in FrequencyOfCare.all)
          RateCardWithUpdater(
            rateCard: current[frequency]!,
            updatedByName: updatedByName[frequency],
            updatedAt: '2026-08-30T10:00:00Z',
          ),
      ];

  @override
  Future<void> update(String frequency, RateCardModel rateCard) async {
    savedRateCards[frequency] = rateCard;
    if (throwOnUpdate) {
      throw ApiException(message: 'Something went wrong', code: 'GEN_003');
    }
    current[frequency] = rateCard;
    updatedByName[frequency] = 'Test Admin';
  }
}

Future<void> _pump(WidgetTester tester, _FakeRateCardRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        rateCardRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: RateCardScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads and displays both the daily and monthly sections independently', (tester) async {
    final repo = _FakeRateCardRepository({
      FrequencyOfCare.daily: _rateCard(frequency: FrequencyOfCare.daily, title: 'Daily Guidelines'),
      FrequencyOfCare.monthly: _rateCard(frequency: FrequencyOfCare.monthly, title: 'Monthly Guidelines'),
    });
    await _pump(tester, repo);

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Daily Guidelines'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Monthly Guidelines'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Companion care'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Care'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, '26000 pm'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Not suggested'), findsNWidgets(2));
  });

  testWidgets('editing and saving the daily section only sends the daily grid, leaving monthly untouched', (tester) async {
    final repo = _FakeRateCardRepository({
      FrequencyOfCare.daily: _rateCard(frequency: FrequencyOfCare.daily, title: 'Daily Guidelines'),
      FrequencyOfCare.monthly: _rateCard(frequency: FrequencyOfCare.monthly, title: 'Monthly Guidelines'),
    });
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Daily Guidelines'), 'Updated Daily');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save').first);
    await tester.pumpAndSettle();

    expect(repo.savedRateCards[FrequencyOfCare.daily], isNotNull);
    expect(repo.savedRateCards[FrequencyOfCare.daily]!.title, 'Updated Daily');
    expect(repo.savedRateCards.containsKey(FrequencyOfCare.monthly), isFalse);
    expect(find.text('Daily rate card saved'), findsOneWidget);
    expect(find.textContaining('Last updated by Test Admin'), findsOneWidget);
    // Monthly section stays untouched.
    expect(find.widgetWithText(TextField, 'Monthly Guidelines'), findsOneWidget);
  });

  testWidgets('shows an error and keeps the edit when saving fails', (tester) async {
    final repo = _FakeRateCardRepository({
      FrequencyOfCare.daily: _rateCard(frequency: FrequencyOfCare.daily, title: 'Daily Guidelines'),
      FrequencyOfCare.monthly: _rateCard(frequency: FrequencyOfCare.monthly, title: 'Monthly Guidelines'),
    }, throwOnUpdate: true);
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Daily Guidelines'), 'Broken Save');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save').first);
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Broken Save'), findsOneWidget);
  });
}
