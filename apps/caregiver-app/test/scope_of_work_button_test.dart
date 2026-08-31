import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/app/scope_of_work_button.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/scope_of_work/scope_of_work_repository.dart';

final _scopeOfWork = ScopeOfWorkModel(
  companionCare: ['Emotional companionship', 'Meal assistance'],
  bedsideCare: ['Diaper changing & hygiene care', 'Feeding assistance'],
  criticalCare: ['Catheter care', 'Vitals monitoring'],
);

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  final ScopeOfWorkModel? result;
  final Object? error;

  _FakeScopeOfWorkRepository({this.result, this.error}) : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async {
    if (error != null) throw error!;
    return result!;
  }
}

CareReceiverModel _careReceiver({
  String feedingType = FeedingType.oralIndependent,
  bool hasMedicalCondition = false,
  List<String> toiletAssistance = const [ToiletAssistance.independent],
  bool requiresVitalMonitoring = false,
}) =>
    CareReceiverModel(
      id: 'cr-1',
      age: 70,
      gender: 'male',
      weightKg: 60,
      communication: Communication.verbal,
      feedingType: feedingType,
      hasMedicalCondition: hasMedicalCondition,
      medicalConditions: const [],
      toiletAssistance: toiletAssistance,
      requiresVitalMonitoring: requiresVitalMonitoring,
      vitalMonitoringTypes: const [],
    );

Future<void> _pump(WidgetTester tester, CareReceiverModel careReceiver, ScopeOfWorkRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [scopeOfWorkRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(body: ScopeOfWorkButton(careReceiver: careReceiver)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a visible "Scope of Work" label', (tester) async {
    await _pump(tester, _careReceiver(), _FakeScopeOfWorkRepository(result: _scopeOfWork));

    expect(find.text('Scope of Work'), findsOneWidget);
  });

  testWidgets('an independent patient opens the Companion Care dialog with only companion bullets', (tester) async {
    await _pump(tester, _careReceiver(), _FakeScopeOfWorkRepository(result: _scopeOfWork));

    await tester.tap(find.text('Scope of Work'));
    await tester.pumpAndSettle();

    expect(find.text('Companion Care'), findsOneWidget);
    expect(find.text('Emotional companionship'), findsOneWidget);
    expect(find.text('Diaper changing & hygiene care'), findsNothing);
    expect(find.text('Catheter care'), findsNothing);
  });

  testWidgets('a patient needing catheter care opens the Critical Care dialog with all 3 tiers stacked', (tester) async {
    await _pump(
      tester,
      _careReceiver(toiletAssistance: const [ToiletAssistance.usesCatheter]),
      _FakeScopeOfWorkRepository(result: _scopeOfWork),
    );

    await tester.tap(find.text('Scope of Work'));
    await tester.pumpAndSettle();

    expect(find.text('Critical Care'), findsOneWidget);
    expect(find.text('Emotional companionship'), findsOneWidget);
    expect(find.text('Diaper changing & hygiene care'), findsOneWidget);
    expect(find.text('Catheter care'), findsOneWidget);
  });

  testWidgets('a patient needing diaper assistance opens the Bedside Care dialog stacking companion + bedside only',
      (tester) async {
    await _pump(
      tester,
      _careReceiver(toiletAssistance: const [ToiletAssistance.usesDiapers]),
      _FakeScopeOfWorkRepository(result: _scopeOfWork),
    );

    await tester.tap(find.text('Scope of Work'));
    await tester.pumpAndSettle();

    expect(find.text('Bedside Care'), findsOneWidget);
    expect(find.text('Emotional companionship'), findsOneWidget);
    expect(find.text('Diaper changing & hygiene care'), findsOneWidget);
    expect(find.text('Catheter care'), findsNothing);
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(tester, _careReceiver(), _FakeScopeOfWorkRepository(error: Exception('network down')));

    await tester.tap(find.text('Scope of Work'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load scope of work'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await _pump(tester, _careReceiver(), _FakeScopeOfWorkRepository(result: _scopeOfWork));

    await tester.tap(find.text('Scope of Work'));
    await tester.pumpAndSettle();
    expect(find.text('Companion Care'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Companion Care'), findsNothing);
  });
}
