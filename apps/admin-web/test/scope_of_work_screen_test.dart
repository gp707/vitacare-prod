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
import 'package:admin_web/features/scope_of_work/data/scope_of_work_repository.dart';
import 'package:admin_web/features/scope_of_work/screens/scope_of_work_screen.dart';

ScopeOfWorkModel _scopeOfWork() {
  return const ScopeOfWorkModel(
    companionCare: ['Emotional companionship', 'Meal assistance'],
    bedsideCare: ['Diaper changing & hygiene care'],
    criticalCare: ['Catheter care', 'Vitals monitoring'],
  );
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  ScopeOfWorkModel current;
  String? updatedByName;
  ScopeOfWorkModel? savedScopeOfWork;
  bool throwOnUpdate;

  _FakeScopeOfWorkRepository(this.current, {this.updatedByName, this.throwOnUpdate = false}) : super(Dio());

  @override
  Future<ScopeOfWorkWithUpdater> get() async => ScopeOfWorkWithUpdater(
        scopeOfWork: current,
        updatedByName: updatedByName,
        updatedAt: '2026-08-30T10:00:00Z',
      );

  @override
  Future<void> update(ScopeOfWorkModel scopeOfWork) async {
    savedScopeOfWork = scopeOfWork;
    if (throwOnUpdate) {
      throw ApiException(message: 'Something went wrong', code: 'GEN_003');
    }
    current = scopeOfWork;
    updatedByName = 'Test Admin';
  }
}

Future<void> _pump(WidgetTester tester, _FakeScopeOfWorkRepository repo) async {
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
        scopeOfWorkRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: ScopeOfWorkScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads and displays the current bullets for all 3 tiers', (tester) async {
    final repo = _FakeScopeOfWorkRepository(_scopeOfWork());
    await _pump(tester, repo);

    expect(find.text('Companion Care'), findsOneWidget);
    expect(find.text('Bedside Care'), findsOneWidget);
    expect(find.text('Critical Care'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Emotional companionship'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Diaper changing & hygiene care'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Catheter care'), findsOneWidget);
  });

  testWidgets('editing a bullet and saving sends the full updated tiers', (tester) async {
    final repo = _FakeScopeOfWorkRepository(_scopeOfWork());
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(TextField, 'Emotional companionship'),
      'Emotional & social companionship',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedScopeOfWork, isNotNull);
    expect(repo.savedScopeOfWork!.companionCare, contains('Emotional & social companionship'));
    expect(repo.savedScopeOfWork!.bedsideCare, _scopeOfWork().bedsideCare);
    expect(find.text('Scope of work saved'), findsOneWidget);
    expect(find.textContaining('Last updated by Test Admin'), findsOneWidget);
  });

  testWidgets('Add bullet appends a new empty field to that tier only', (tester) async {
    final repo = _FakeScopeOfWorkRepository(_scopeOfWork());
    await _pump(tester, repo);

    expect(find.widgetWithText(TextField, ''), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Add bullet').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, ''), 'New companion task');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedScopeOfWork!.companionCare, contains('New companion task'));
    expect(repo.savedScopeOfWork!.companionCare.length, 3);
  });

  testWidgets('removing a bullet drops it from the saved tier', (tester) async {
    final repo = _FakeScopeOfWorkRepository(_scopeOfWork());
    await _pump(tester, repo);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.savedScopeOfWork!.companionCare, ['Meal assistance']);
  });

  testWidgets('shows an error and keeps the edit when saving fails', (tester) async {
    final repo = _FakeScopeOfWorkRepository(_scopeOfWork(), throwOnUpdate: true);
    await _pump(tester, repo);

    await tester.enterText(find.widgetWithText(TextField, 'Emotional companionship'), 'Broken Save');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Broken Save'), findsOneWidget);
  });
}
