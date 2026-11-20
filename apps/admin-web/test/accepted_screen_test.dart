import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/accepted/data/admin_accepted_repository.dart';
import 'package:admin_web/features/accepted/screens/accepted_screen.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';

AdminAcceptedItem _item({
  String status = 'accepted',
  String caregiverName = 'Sunandita Nandy',
  int caregiverNumber = 589,
  int? patientJobNumber = 548,
  int? requirementNumber,
  String posterRole = 'individual',
  String posterName = 'Krishna Sapra',
  int posterNumber = 636,
  String? acceptedByName = 'Krishna Sapra',
  String? acceptedByRole = 'individual',
  int? agreedSalary = 30000,
  String? agreedSalaryUnit = 'monthly',
  String? agreedStartDate = '2026-11-01',
}) =>
    AdminAcceptedItem(
      kind: requirementNumber != null ? 'organisation_requirement' : 'job',
      applicationId: 'a-$caregiverNumber-$status',
      status: status,
      acceptedAt: '2026-11-17T10:00:00Z',
      caregiverProfileId: 'cp-$caregiverNumber',
      caregiverNumber: caregiverNumber,
      caregiverName: caregiverName,
      caregiverPhone: '+919233416460',
      patientJobNumber: patientJobNumber,
      requirementNumber: requirementNumber,
      posterName: posterName,
      posterRole: posterRole,
      posterNumber: posterNumber,
      acceptedByName: acceptedByName,
      acceptedByRole: acceptedByRole,
      agreedSalary: agreedSalary,
      agreedSalaryUnit: agreedSalaryUnit,
      agreedStartDate: agreedStartDate,
    );

class _FakeRepo extends AdminAcceptedRepository {
  final List<AdminAcceptedItem> items;
  String? lastStatus;
  String? lastSearch;
  int calls = 0;

  _FakeRepo(this.items) : super(Dio());

  @override
  Future<AdminAcceptedListResult> list({int page = 1, int limit = 20, String? status, String? search}) async {
    calls++;
    lastStatus = status;
    lastSearch = search;
    return AdminAcceptedListResult(
      items: items,
      meta: PaginationMeta(page: 1, limit: 20, total: items.length, totalPages: items.isEmpty ? 0 : 1),
    );
  }
}

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  await tester.binding.setSurfaceSize(const Size(2200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminAcceptedRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: MaterialApp(
        home: const AcceptedScreen(),
        onGenerateRoute: (settings) =>
            MaterialPageRoute(builder: (_) => Scaffold(body: Text('opened ${settings.name}:${settings.arguments}'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows who was accepted, onto which job, by whom, and what was agreed', (tester) async {
    await _pump(tester, _FakeRepo([_item()]));
    expect(find.text('NUR-589  Sunandita Nandy'), findsOneWidget);
    expect(find.text('PAT-JOB-548'), findsOneWidget);
    expect(find.text('Krishna Sapra\nPAT-636'), findsOneWidget); // posted by
    expect(find.text('Krishna Sapra'), findsOneWidget); // accepted by
    expect(find.textContaining('₹30,000 per month'), findsOneWidget);
    expect(find.textContaining('Cycle from'), findsOneWidget);
    expect(find.text('2026-11-17'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
  });

  testWidgets('labels each current status in plain words', (tester) async {
    await _pump(
      tester,
      _FakeRepo([
        _item(status: 'accepted', caregiverNumber: 571),
        _item(status: 'completed', caregiverNumber: 591),
        _item(status: 'rejected', caregiverNumber: 565, acceptedByName: null, acceptedByRole: null),
        _item(status: 'applied', caregiverNumber: 592, acceptedByName: null, acceptedByRole: null),
      ]),
    );
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Closed duty'), findsOneWidget);
    expect(find.text('Later rejected'), findsOneWidget);
    expect(find.text('Re-applied'), findsOneWidget);
  });

  testWidgets('an organisation requirement shows ORG-JOB and the organisation', (tester) async {
    await _pump(
      tester,
      _FakeRepo([
        _item(
          patientJobNumber: null,
          requirementNumber: 574,
          posterRole: 'organisation',
          posterName: 'Vita Health',
          posterNumber: 500,
          acceptedByName: 'Veer',
          agreedSalary: null,
          agreedSalaryUnit: null,
          agreedStartDate: null,
        ),
      ]),
    );
    expect(find.text('ORG-JOB-574'), findsOneWidget);
    expect(find.text('Vita Health\nORG-500'), findsOneWidget);
    expect(find.text('Veer'), findsOneWidget);
  });

  testWidgets('an admin who accepted is marked as admin; a later-rejected row has no accepter', (tester) async {
    await _pump(
      tester,
      _FakeRepo([
        _item(caregiverNumber: 571, acceptedByName: 'Pankaj', acceptedByRole: 'admin'),
        _item(status: 'rejected', caregiverNumber: 565, acceptedByName: null, acceptedByRole: null),
      ]),
    );
    expect(find.text('Pankaj (admin)'), findsOneWidget);
  });

  testWidgets('says so when nobody matches', (tester) async {
    await _pump(tester, _FakeRepo([]));
    expect(find.byKey(const Key('accepted-empty')), findsOneWidget);
  });

  testWidgets('the status filter and the search are sent to the server', (tester) async {
    final repo = _FakeRepo([_item()]);
    await _pump(tester, repo);
    expect(repo.calls, 1);
    await tester.tap(find.byKey(const Key('accepted-filter-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed duty').last);
    await tester.pumpAndSettle();
    expect(repo.lastStatus, 'completed');

    await tester.enterText(find.byKey(const Key('accepted-search')), 'NUR-589');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.lastSearch, 'NUR-589');
  });

  testWidgets('tapping the caregiver opens their detail screen', (tester) async {
    await _pump(tester, _FakeRepo([_item()]));
    await tester.tap(find.text('NUR-589  Sunandita Nandy'));
    await tester.pumpAndSettle();
    expect(find.text('opened /caregiver-detail:cp-589'), findsOneWidget);
  });
}
