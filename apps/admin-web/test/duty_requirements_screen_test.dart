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
import 'package:admin_web/features/duty_requirements/data/duty_requirements_repository.dart';
import 'package:admin_web/features/duty_requirements/screens/duty_requirements_screen.dart';

DutyRequirementsModel _dutyRequirements() {
  return const DutyRequirementsModel(
    liveIn: ['Bed, bedsheet, pillow and blanket must be provided.', '3 meals daily for the nurse.'],
    dayDuty: ['Breakfast and lunch for the nurse.'],
    nightDuty: ['Dinner and breakfast for the nurse.', 'Arrival up to 9:00 PM may be mutually agreed.'],
  );
}

class _FakeDutyRequirementsRepository extends DutyRequirementsRepository {
  DutyRequirementsModel current;
  String? updatedByName;
  DutyRequirementsModel? savedDutyRequirements;
  bool throwOnUpdate;

  _FakeDutyRequirementsRepository(this.current, {this.updatedByName, this.throwOnUpdate = false}) : super(Dio());

  @override
  Future<DutyRequirementsWithUpdater> get() async => DutyRequirementsWithUpdater(
        dutyRequirements: current,
        updatedByName: updatedByName,
        updatedAt: '2026-08-30T10:00:00Z',
      );

  @override
  Future<void> update(DutyRequirementsModel dutyRequirements) async {
    savedDutyRequirements = dutyRequirements;
    if (throwOnUpdate) {
      throw ApiException(message: 'Something went wrong', code: 'GEN_003');
    }
    current = dutyRequirements;
    updatedByName = 'Test Admin';
  }
}

Future<void> _pump(WidgetTester tester, _FakeDutyRequirementsRepository repo) async {
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
        dutyRequirementsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: DutyRequirementsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads and displays the current bullets for all 3 shifts', (tester) async {
    final repo = _FakeDutyRequirementsRepository(_dutyRequirements());
    await _pump(tester, repo);

    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('12Hrs Day Shift (8am to 8pm)'), findsOneWidget);
    expect(find.text('12Hrs Night Shift (8pm to 8am)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bed, bedsheet, pillow and blanket must be provided.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Breakfast and lunch for the nurse.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Dinner and breakfast for the nurse.'), findsOneWidget);
  });

  testWidgets('editing a bullet and saving sends the full updated lists', (tester) async {
    final repo = _FakeDutyRequirementsRepository(_dutyRequirements());
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Breakfast and lunch for the nurse.'),
      'Breakfast, lunch and snacks for the nurse.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedDutyRequirements, isNotNull);
    expect(repo.savedDutyRequirements!.dayDuty, contains('Breakfast, lunch and snacks for the nurse.'));
    expect(repo.savedDutyRequirements!.liveIn, _dutyRequirements().liveIn);
    expect(find.text('Duty requirements saved'), findsOneWidget);
    expect(find.textContaining('Last updated by Test Admin'), findsOneWidget);
  });

  testWidgets('Add bullet appends a new empty field to that shift only', (tester) async {
    final repo = _FakeDutyRequirementsRepository(_dutyRequirements());
    await _pump(tester, repo);

    expect(find.widgetWithText(TextField, ''), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Add bullet').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, ''), 'New live-in task');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedDutyRequirements!.liveIn, contains('New live-in task'));
    expect(repo.savedDutyRequirements!.liveIn.length, 3);
  });

  testWidgets('removing a bullet drops it from the saved shift', (tester) async {
    final repo = _FakeDutyRequirementsRepository(_dutyRequirements());
    await _pump(tester, repo);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedDutyRequirements!.liveIn, ['3 meals daily for the nurse.']);
  });

  testWidgets('shows an error and keeps the edit when saving fails', (tester) async {
    final repo = _FakeDutyRequirementsRepository(_dutyRequirements(), throwOnUpdate: true);
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Breakfast and lunch for the nurse.'),
      'Broken Save',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Broken Save'), findsOneWidget);
  });
}
