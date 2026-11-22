import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
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
import 'package:admin_web/features/caregivers/data/admin_caregiver_models.dart';
import 'package:admin_web/features/caregivers/data/admin_caregivers_repository.dart';
import 'package:admin_web/features/caregivers/screens/caregiver_list_screen.dart';
import 'package:admin_web/features/jobs/data/admin_jobs_repository.dart';
import 'package:admin_web/features/jobs/widgets/job_detail_dialog.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';
import 'package:admin_web/features/organisation_requirements/widgets/requirement_widgets.dart';
import 'package:admin_web/features/organisations/data/admin_organisations_repository.dart';

CaregiverAssignment _job({String id = 'job-uuid-539', String label = 'PAT-JOB-539', String poster = 'Hansa', String? posterId = 'pat-user-625'}) =>
    CaregiverAssignment(
      isRequirement: false,
      jobId: id,
      label: label,
      posterId: posterId,
      posterName: poster,
      posterRole: 'individual',
      posterNumber: 625,
      city: 'bangalore',
      shift: 'live_in',
      acceptedAt: '2026-11-07T12:13:55Z',
    );

CaregiverAssignment _requirement() => const CaregiverAssignment(
      isRequirement: true,
      jobId: 'req-uuid-574',
      label: 'ORG-JOB-574',
      posterId: 'org-user-500',
      posterName: 'Vita Health',
      posterRole: 'organisation',
      posterNumber: 500,
      city: 'bangalore',
      acceptedAt: '2026-11-08T12:13:55Z',
    );

AdminCaregiverListItem _item({
  String status = 'assigned',
  List<CaregiverAssignment>? assignments = const [],
  String profileId = 'profile-1',
}) =>
    AdminCaregiverListItem(
      userId: 'u1',
      profileId: profileId,
      caregiverNumber: 574,
      fullName: 'vita health dummy',
      phone: '+918792902302',
      gender: 'male',
      age: 25,
      highestQualification: 'registered_recently',
      verificationStatus: status,
      createdAt: '2026-08-01T10:00:00Z',
      assignments: assignments,
    );

class _FakeRepo extends AdminCaregiversRepository {
  final List<AdminCaregiverListItem> items;
  _FakeRepo(this.items) : super(Dio());

  @override
  Future<CaregiverListResult> list(CaregiverListFilters filters) async => CaregiverListResult(
        items: items,
        meta: PaginationMeta(page: 1, limit: 20, total: items.length, totalPages: 1),
      );
}

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
          'organisation_name': 'Vita Health',
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
        'organisation_name': 'Vita Health',
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

Future<void> _pump(WidgetTester tester, List<AdminCaregiverListItem> items) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(2200, 900));
  tester.view.physicalSize = const Size(2200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.view.reset();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminCaregiversRepositoryProvider.overrideWithValue(_FakeRepo(items)),
        adminJobsRepositoryProvider.overrideWithValue(_FakeJobsRepo()),
        adminOrganisationRequirementsRepositoryProvider.overrideWithValue(_FakeRequirementsRepo()),
        adminOrganisationsRepositoryProvider.overrideWithValue(_FakeOrgsRepo()),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: MaterialApp(
        home: const CaregiverListScreen(),
        onGenerateRoute: (settings) =>
            MaterialPageRoute(builder: (_) => Scaffold(body: Text('opened ${settings.name}:${settings.arguments}'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _hover(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder get _statusBadge => find.text('Assigned');

void main() {
  testWidgets('hovering an assigned caregiver\'s status shows the patient\'s name and id', (tester) async {
    await _pump(tester, [_item(assignments: [_job()])]);
    await _hover(tester, _statusBadge);
    expect(find.textContaining('Assigned to:'), findsOneWidget);
    expect(find.textContaining('• Hansa · PAT-625'), findsOneWidget);
    expect(find.textContaining('Click to see them'), findsOneWidget);
    expect(find.textContaining('in parallel'), findsNothing);
  });

  testWidgets('several patients / an organisation are all listed by name and id on hover', (tester) async {
    await _pump(tester, [
      _item(assignments: [_job(), _job(id: 'job-uuid-548', label: 'PAT-JOB-548', poster: 'Krishna Sapra', posterId: 'pat-user-2'), _requirement()]),
    ]);
    await _hover(tester, _statusBadge);
    expect(find.textContaining('Assigned to 3 (in parallel):'), findsOneWidget);
    expect(find.textContaining('• Hansa · PAT-625'), findsOneWidget);
    expect(find.textContaining('• Krishna Sapra'), findsOneWidget);
    expect(find.textContaining('• Vita Health · ORG-500'), findsOneWidget);
  });

  testWidgets('clicking opens the Patients/Family list narrowed to the patients she is assigned to', (tester) async {
    await _pump(tester, [
      _item(assignments: [_job(), _job(id: 'job-uuid-548', label: 'PAT-JOB-548', poster: 'Krishna Sapra', posterId: 'pat-user-2')]),
    ]);
    await tester.tap(_statusBadge);
    await tester.pumpAndSettle();
    expect(find.text('opened /patients-family:AssignedAccountsFilter(pat-user-625,pat-user-2; vita health dummy)'.replaceAll('pat-user-625', 'pat-user-625')), findsOneWidget);
  });

  testWidgets('one organisation: opens the Rehab/Hospitals list narrowed to it', (tester) async {
    await _pump(tester, [_item(assignments: [_requirement()])]);
    await tester.tap(_statusBadge);
    await tester.pumpAndSettle();
    expect(find.text('opened /rehab-hospitals:AssignedAccountsFilter(org-user-500; vita health dummy)'), findsOneWidget);
  });

  testWidgets('assigned to both a patient and an organisation: asks which list to open', (tester) async {
    await _pump(tester, [_item(assignments: [_job(), _requirement()])]);
    await tester.tap(_statusBadge);
    await tester.pumpAndSettle();
    expect(find.text('Patients / families (1)'), findsOneWidget);
    expect(find.text('Rehabs / hospitals (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assigned-open-organisations')));
    await tester.pumpAndSettle();
    expect(find.text('opened /rehab-hospitals:AssignedAccountsFilter(org-user-500; vita health dummy)'), findsOneWidget);
  });

  testWidgets('an admin-posted job has no patient: a click still opens the job itself', (tester) async {
    await _pump(tester, [
      _item(assignments: [
        const CaregiverAssignment(isRequirement: false, jobId: 'job-admin-1', label: 'ADMIN-JOB-512', acceptedAt: '2026-11-07T12:13:55Z'),
      ]),
    ]);
    await _hover(tester, _statusBadge);
    expect(find.textContaining('Admin-posted job (ADMIN-JOB-512)'), findsOneWidget);
    expect(find.textContaining('Click to open the job'), findsOneWidget);
    await tester.tap(_statusBadge);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(JobDetailDialog), findsOneWidget);
  });

  testWidgets('when the server did not send the job list at all, the hover claims nothing about jobs and a click opens the profile', (tester) async {
    await _pump(tester, [_item(assignments: null)]);
    await _hover(tester, _statusBadge);
    expect(find.textContaining('not accepted onto any job'), findsNothing);
    expect(find.textContaining('Assigned to ('), findsNothing);
    expect(find.textContaining('Click to open the profile'), findsOneWidget);
    await tester.tap(_statusBadge);
    await tester.pumpAndSettle();
    expect(find.text('opened /caregiver-detail:profile-1'), findsOneWidget);
  });

  test('the model tells "not sent" (null) apart from "sent, and empty"', () {
    Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
          'user_id': 'u1',
          'profile_id': 'p1',
          'full_name': 'X',
          'phone': '+919999999999',
          'gender': 'male',
          'age': 30,
          'verification_status': 'assigned',
          'created_at': '2026-01-01T00:00:00Z',
          ...extra,
        };
    expect(AdminCaregiverListItem.fromJson(row()).assignments, isNull);
    expect(AdminCaregiverListItem.fromJson(row({'assignments': []})).assignments, isEmpty);
    final one = AdminCaregiverListItem.fromJson(row({
      'assignments': [
        {'kind': 'job', 'job_id': 'j1', 'label': 'PAT-JOB-539', 'poster_name': 'Hansa', 'poster_role': 'individual', 'poster_number': 625},
      ],
    }));
    expect(one.assignments, hasLength(1));
    expect(one.assignmentHoverText, contains('Assigned to:'));
  });

  testWidgets('an "assigned" status the server says has nothing behind it says so, and a click opens the caregiver\'s profile', (tester) async {
    await _pump(tester, [_item()]);
    await _hover(tester, _statusBadge);
    expect(find.textContaining('not accepted onto any job or requirement'), findsOneWidget);
    await tester.tap(_statusBadge);
    await tester.pumpAndSettle();
    expect(find.text('opened /caregiver-detail:profile-1'), findsOneWidget);
  });

  testWidgets('a caregiver who is not assigned has no hover card and a click still opens the profile', (tester) async {
    await _pump(tester, [_item(status: 'available')]);
    await _hover(tester, find.text('Available'));
    expect(find.textContaining('Assigned to'), findsNothing);
    await tester.tap(find.text('Available'));
    await tester.pumpAndSettle();
    expect(find.text('opened /caregiver-detail:profile-1'), findsOneWidget);
  });
}
