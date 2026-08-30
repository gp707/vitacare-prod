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

RateCardModel _rateCard({String title = 'Salary Guidelines'}) {
  return RateCardModel(
    title: title,
    columnLabels: ['Companion care', 'Bedside Care', 'Critical Care'],
    rowLabels: ['Caregivers', 'Nursing students', 'Nurses'],
    cells: [
      ['26000 pm', '28000 pm', 'Not suggested'],
      ['28000 pm', '30000 pm', '32000 pm'],
      ['30000 pm', '32000 pm', '35000-42000 pm'],
    ],
  );
}

class _FakeRateCardRepository extends RateCardRepository {
  RateCardModel current;
  String? updatedByName;
  RateCardModel? savedRateCard;
  bool throwOnUpdate;

  _FakeRateCardRepository(this.current, {this.updatedByName, this.throwOnUpdate = false}) : super(Dio());

  @override
  Future<RateCardWithUpdater> get() async => RateCardWithUpdater(
        rateCard: current,
        updatedByName: updatedByName,
        updatedAt: '2026-08-30T10:00:00Z',
      );

  @override
  Future<void> update(RateCardModel rateCard) async {
    savedRateCard = rateCard;
    if (throwOnUpdate) {
      throw ApiException(message: 'Something went wrong', code: 'GEN_003');
    }
    current = rateCard;
    updatedByName = 'Test Admin';
  }
}

Future<void> _pump(WidgetTester tester, _FakeRateCardRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
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
  testWidgets('loads and displays the current title, labels, and cells', (tester) async {
    final repo = _FakeRateCardRepository(_rateCard());
    await _pump(tester, repo);

    expect(find.widgetWithText(TextField, 'Salary Guidelines'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Companion care'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Caregivers'), findsOneWidget);
    expect(find.widgetWithText(TextField, '26000 pm'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Not suggested'), findsOneWidget);
  });

  testWidgets('editing a cell and saving sends the full updated grid', (tester) async {
    final repo = _FakeRateCardRepository(_rateCard());
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Not suggested'), 'Now allowed: 40000 pm');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedRateCard, isNotNull);
    expect(repo.savedRateCard!.cells[0][2], 'Now allowed: 40000 pm');
    expect(repo.savedRateCard!.title, 'Salary Guidelines');
    expect(find.text('Rate card saved'), findsOneWidget);
    expect(find.textContaining('Last updated by Test Admin'), findsOneWidget);
  });

  testWidgets('shows an error and keeps the edit when saving fails', (tester) async {
    final repo = _FakeRateCardRepository(_rateCard(), throwOnUpdate: true);
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Salary Guidelines'), 'Broken Save');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Broken Save'), findsOneWidget);
  });
}
