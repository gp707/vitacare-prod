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
import 'package:admin_web/core/network/api_exception.dart';
import 'package:admin_web/features/jobs/data/admin_jobs_repository.dart';
import 'package:admin_web/features/jobs/widgets/job_detail_dialog.dart';
import 'package:admin_web/features/organisations/data/admin_organisations_repository.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';
import 'package:admin_web/features/organisation_requirements/widgets/requirement_widgets.dart';
import 'package:flutter/gestures.dart';

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
  String acceptedByUserId = 'patient-1',
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
      jobId: requirementNumber != null ? 'req-uuid-$requirementNumber' : 'job-uuid-$patientJobNumber',
      jobCity: 'bangalore',
      jobArea: 'Whitefield',
      jobShift: requirementNumber != null ? null : 'live_in',
      jobTypeOfNurse: requirementNumber != null ? 'registered_nurse' : null,
      jobSalary: requirementNumber != null ? null : '1067 - 1500',
      jobFrequency: requirementNumber != null ? null : 'daily',
      caregiverAge: 26,
      caregiverGender: 'male',
      caregiverQualification: 'gda_non_nursing',
      caregiverStatus: 'assigned',
      acceptedById: acceptedByName == null ? null : acceptedByUserId,
      acceptedByPhone: acceptedByName == null ? null : '+919845204336',
      acceptedByNumber: acceptedByRole == 'admin' ? null : 636,
    );

class _FakeJobsRepo implements AdminJobsRepository {
  @override
  Future<(JobModel, List<JobApplicationModel>)> getDetail(String jobId) async =>
      throw const ApiException(code: 'GEN_002', message: 'not needed in this test');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeRequirementsRepo implements AdminOrganisationRequirementsRepository {
  @override
  Future<(AdminOrganisationRequirement, List<OrganisationRequirementApplicationModel>)> getDetail(String id) async => (
        AdminOrganisationRequirement.fromJson({
          'id': id,
          'posted_by': 'org-user-1',
          'requirement_number': 574,
          'status': 'active',
          'type_of_nurse': 'registered_nurse',
          'number_of_vacancies': 1,
          'accommodation_provided': false,
          'food_provided': false,
          'posted_at': '2026-01-01T00:00:00Z',
          'created_at': '2026-01-01T00:00:00Z',
          'organisation_name': 'Test Hospital',
        }),
        <OrganisationRequirementApplicationModel>[],
      );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeOrgsRepo implements AdminOrganisationsRepository {
  @override
  Future<AdminOrganisationListItem> getDetail(String userId) async => AdminOrganisationListItem.fromJson({
        'user_id': userId,
        'full_name': 'Maria',
        'phone': '+919800000001',
        'organisation_name': 'Test Hospital',
        'organisation_type': 'hospital',
        'city': 'bangalore',
        'area': 'x',
        'is_active': true,
        'is_job_posting_blocked': false,
        'created_at': '2026-01-01T00:00:00Z',
      });

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

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
        adminJobsRepositoryProvider.overrideWithValue(_FakeJobsRepo()),
        adminOrganisationRequirementsRepositoryProvider.overrideWithValue(_FakeRequirementsRepo()),
        adminOrganisationsRepositoryProvider.overrideWithValue(_FakeOrgsRepo()),
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
    expect(find.textContaining('Starts 1 Nov 2026'), findsOneWidget);
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

  group('hover details and click-through', () {
    Future<void> hover(WidgetTester tester, Finder target) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    testWidgets('hovering the caregiver shows their details', (tester) async {
      await _pump(tester, _FakeRepo([_item()]));
      await hover(tester, find.text('NUR-589  Sunandita Nandy'));
      expect(find.textContaining('Age 26 · Male'), findsOneWidget);
      expect(find.textContaining('Qualification: GDA'), findsOneWidget);
      expect(find.textContaining('Status: assigned'), findsOneWidget);
      expect(find.textContaining('Click to open their profile'), findsOneWidget);
    });

    testWidgets('hovering the job shows its details', (tester) async {
      await _pump(tester, _FakeRepo([_item()]));
      await hover(tester, find.text('PAT-JOB-548'));
      expect(find.textContaining('Posted by: Krishna Sapra PAT-636'), findsOneWidget);
      expect(find.textContaining('Bangalore · Whitefield'), findsOneWidget);
      expect(find.textContaining('Shift: 24Hrs - Live In'), findsOneWidget);
      expect(find.textContaining('Offered: 1067 - 1500 per day'), findsOneWidget);
      expect(find.textContaining('Click to open this job'), findsOneWidget);
    });

    testWidgets('an organisation requirement\'s hover says what is being looked for', (tester) async {
      await _pump(
        tester,
        _FakeRepo([_item(patientJobNumber: null, requirementNumber: 574, posterRole: 'organisation', posterName: 'Vita Health', acceptedByRole: 'organisation')]),
      );
      await hover(tester, find.text('ORG-JOB-574'));
      expect(find.textContaining('Looking for: Registered Nurse'), findsOneWidget);
      expect(find.textContaining('Click to open this requirement'), findsOneWidget);
    });

    testWidgets('hovering "Accepted by" shows who it is, their role, id and phone', (tester) async {
      await _pump(tester, _FakeRepo([_item()]));
      await hover(tester, find.byKey(const Key('accepted-by-a-589-accepted')));
      expect(find.textContaining('Krishna Sapra · PAT-636'), findsOneWidget);
      expect(find.textContaining('Role: patient/family'), findsOneWidget);
      expect(find.textContaining('Phone: +919845204336'), findsOneWidget);
      expect(find.textContaining('Click to open their profile'), findsOneWidget);
    });

    testWidgets('clicking "Accepted by" opens the patient\'s profile', (tester) async {
      await _pump(tester, _FakeRepo([_item()]));
      await tester.tap(find.byKey(const Key('accepted-by-a-589-accepted')));
      await tester.pumpAndSettle();
      expect(find.text('opened /individual-detail:patient-1'), findsOneWidget);
    });

    testWidgets('clicking "Accepted by" for an organisation opens the organisation\'s profile', (tester) async {
      await _pump(
        tester,
        _FakeRepo([_item(posterRole: 'organisation', acceptedByRole: 'organisation', acceptedByUserId: 'org-user-1')]),
      );
      await tester.tap(find.byKey(const Key('accepted-by-a-589-accepted')));
      await tester.pumpAndSettle();
      expect(find.text('opened /organisation-detail:org-user-1'), findsOneWidget);
    });

    testWidgets('an admin who accepted has a hover card but nothing to click through to', (tester) async {
      await _pump(tester, _FakeRepo([_item(acceptedByName: 'Pankaj', acceptedByRole: 'admin')]));
      await hover(tester, find.byKey(const Key('accepted-by-a-589-accepted')));
      expect(find.textContaining('Role: admin'), findsOneWidget);
      expect(find.textContaining('Click to open their profile'), findsNothing);
      await tester.tap(find.byKey(const Key('accepted-by-a-589-accepted')));
      await tester.pumpAndSettle();
      expect(find.textContaining('opened /individual-detail'), findsNothing);
      expect(find.textContaining('opened /organisation-detail'), findsNothing);
    });

    testWidgets('clicking the job opens that job in place (the job detail dialog)', (tester) async {
      await _pump(tester, _FakeRepo([_item()]));
      await tester.tap(find.byKey(const Key('accepted-job-a-589-accepted')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(JobDetailDialog), findsOneWidget);
      expect(tester.widget<JobDetailDialog>(find.byType(JobDetailDialog)).jobId, 'job-uuid-548');
    });

    testWidgets('clicking an organisation requirement opens its detail', (tester) async {
      await _pump(
        tester,
        _FakeRepo([_item(patientJobNumber: null, requirementNumber: 574, posterRole: 'organisation', posterName: 'Vita Health')]),
      );
      await tester.tap(find.byKey(const Key('accepted-job-a-589-accepted')));
      await tester.pumpAndSettle();
      expect(find.byType(RequirementReadOnlyDialog), findsOneWidget);
      expect(find.text('Test Hospital'), findsWidgets);
    });
  });
}
