import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/duty_requirements/duty_requirements_repository.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/features/individual/widgets/duty_requirements_button.dart';

final _dutyRequirements = DutyRequirementsModel(
  liveIn: ['Bed, bedsheet, pillow and blanket must be provided.', '6–7 hours of continuous sleep must be ensured.'],
  dayDuty: ['Breakfast and lunch for the nurse.'],
  nightDuty: ['Dinner and breakfast for the nurse.', 'Arrival up to 9:00 PM may be mutually agreed.'],
);

class _FakeDutyRequirementsRepository extends DutyRequirementsRepository {
  final DutyRequirementsModel? result;
  final Object? error;

  _FakeDutyRequirementsRepository({this.result, this.error}) : super(Dio());

  @override
  Future<DutyRequirementsModel> get() async {
    if (error != null) throw error!;
    return result!;
  }
}

Future<void> _pump(WidgetTester tester, String? dutyType, DutyRequirementsRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dutyRequirementsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(body: DutyRequirementsInfoButton(dutyType: dutyType)),
      ),
    ),
  );
}

void main() {
  testWidgets('is disabled with no shift selected', (tester) async {
    await _pump(tester, null, _FakeDutyRequirementsRepository(result: _dutyRequirements));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping it for live_in shows the 24Hrs Live-In requirements', (tester) async {
    await _pump(tester, DutyType.liveIn, _FakeDutyRequirementsRepository(result: _dutyRequirements));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.textContaining('Bed, bedsheet, pillow and blanket must be provided.'), findsOneWidget);
    expect(find.textContaining('6–7 hours of continuous sleep must be ensured.'), findsOneWidget);
    // Day/night-specific content shouldn't leak into the live-in dialog.
    expect(find.textContaining('Breakfast and lunch for the nurse.'), findsNothing);
    expect(find.textContaining('Dinner and breakfast for the nurse.'), findsNothing);
  });

  testWidgets('tapping it for day_duty shows the day shift requirements', (tester) async {
    await _pump(tester, DutyType.dayDuty, _FakeDutyRequirementsRepository(result: _dutyRequirements));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('12Hrs Day Shift (8am to 8pm)'), findsOneWidget);
    expect(find.textContaining('Breakfast and lunch for the nurse.'), findsOneWidget);
  });

  testWidgets('tapping it for night_duty shows the night shift requirements', (tester) async {
    await _pump(tester, DutyType.nightDuty, _FakeDutyRequirementsRepository(result: _dutyRequirements));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('12Hrs Night Shift (8pm to 8am)'), findsOneWidget);
    expect(find.textContaining('Dinner and breakfast for the nurse.'), findsOneWidget);
    expect(find.textContaining('Arrival up to 9:00 PM may be mutually agreed.'), findsOneWidget);
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(tester, DutyType.liveIn, _FakeDutyRequirementsRepository(error: Exception('network down')));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load duty requirements'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await _pump(tester, DutyType.liveIn, _FakeDutyRequirementsRepository(result: _dutyRequirements));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.text('24Hrs - Live In'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('24Hrs - Live In'), findsNothing);
  });
}
