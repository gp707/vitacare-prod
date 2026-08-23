import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/reports/data/admin_reports_repository.dart';
import 'package:admin_web/features/reports/screens/reports_screen.dart';

class _FakeAdminReportsRepository extends AdminReportsRepository {
  List<Map<String, dynamic>> unassignedOrNoDutyResult;
  List<Map<String, dynamic>> stalledDutyResult;
  List<Map<String, dynamic>> overThresholdActiveResult;
  List<Map<String, dynamic>> activityResult;
  List<Map<String, dynamic>> patientNoApplicantsResult;
  List<Map<String, dynamic>> patientNoPendingCandidateResult;
  List<Map<String, dynamic>> patientUnconvertedApplicantsResult;
  List<Map<String, dynamic>> patientActivityResult;
  List<Map<String, dynamic>> organisationNoJobsPostedResult;
  List<Map<String, dynamic>> organisationNoApplicantsResult;
  List<Map<String, dynamic>> organisationUnconvertedApplicantsResult;
  List<Map<String, dynamic>> organisationActivityResult;

  int? capturedStalledDutyDays;
  int? capturedMinJobs;
  int? capturedActivityDays;
  String? capturedActivityOrder;
  int? capturedPatientNoApplicantsDays;
  int? capturedPatientActivityDays;
  String? capturedPatientActivityOrder;
  bool patientNoPendingCandidateCalled = false;
  bool patientUnconvertedApplicantsCalled = false;
  bool organisationNoJobsPostedCalled = false;
  int? capturedOrganisationNoApplicantsDays;
  bool organisationUnconvertedApplicantsCalled = false;
  int? capturedOrganisationActivityDays;
  String? capturedOrganisationActivityOrder;

  _FakeAdminReportsRepository({
    this.unassignedOrNoDutyResult = const [],
    this.stalledDutyResult = const [],
    this.overThresholdActiveResult = const [],
    this.activityResult = const [],
    this.patientNoApplicantsResult = const [],
    this.patientNoPendingCandidateResult = const [],
    this.patientUnconvertedApplicantsResult = const [],
    this.patientActivityResult = const [],
    this.organisationNoJobsPostedResult = const [],
    this.organisationNoApplicantsResult = const [],
    this.organisationUnconvertedApplicantsResult = const [],
    this.organisationActivityResult = const [],
  }) : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> unassignedOrNoDutyCaregivers() async => unassignedOrNoDutyResult;

  @override
  Future<List<Map<String, dynamic>>> stalledDutyCaregivers(int days) async {
    capturedStalledDutyDays = days;
    return stalledDutyResult;
  }

  @override
  Future<List<Map<String, dynamic>>> overThresholdActiveCaregivers(int minJobs) async {
    capturedMinJobs = minJobs;
    return overThresholdActiveResult;
  }

  @override
  Future<List<Map<String, dynamic>>> caregiverActivity(int days, {String order = 'desc'}) async {
    capturedActivityDays = days;
    capturedActivityOrder = order;
    return activityResult;
  }

  @override
  Future<List<Map<String, dynamic>>> patientsWithNoApplicants(int days) async {
    capturedPatientNoApplicantsDays = days;
    return patientNoApplicantsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> patientsWithNoPendingCandidate() async {
    patientNoPendingCandidateCalled = true;
    return patientNoPendingCandidateResult;
  }

  @override
  Future<List<Map<String, dynamic>>> patientsWithUnconvertedApplicants() async {
    patientUnconvertedApplicantsCalled = true;
    return patientUnconvertedApplicantsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> patientActivity(int days, {String order = 'desc'}) async {
    capturedPatientActivityDays = days;
    capturedPatientActivityOrder = order;
    return patientActivityResult;
  }

  @override
  Future<List<Map<String, dynamic>>> organisationsWithNoJobsPosted() async {
    organisationNoJobsPostedCalled = true;
    return organisationNoJobsPostedResult;
  }

  @override
  Future<List<Map<String, dynamic>>> organisationsWithNoApplicants(int days) async {
    capturedOrganisationNoApplicantsDays = days;
    return organisationNoApplicantsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> organisationsWithUnconvertedApplicants() async {
    organisationUnconvertedApplicantsCalled = true;
    return organisationUnconvertedApplicantsResult;
  }

  @override
  Future<List<Map<String, dynamic>>> organisationActivity(int days, {String order = 'desc'}) async {
    capturedOrganisationActivityDays = days;
    capturedOrganisationActivityOrder = order;
    return organisationActivityResult;
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminReportsRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
        adminReportsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: ReportsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists all 4 caregiver, 4 patient, and 4 organisation reports, none selected initially', (tester) async {
    await _pump(tester, _FakeAdminReportsRepository());

    expect(find.text('Unassigned or No Duty'), findsOneWidget);
    expect(find.text('Assigned, Duty Not Completed in N Days'), findsOneWidget);
    expect(find.text('More Than X Jobs Accepted, Not Completed'), findsOneWidget);
    expect(find.text('Caregiver Activity (Most/Least Active)'), findsOneWidget);
    expect(find.text('No Caregiver Applied in N Days'), findsOneWidget);
    expect(find.text('Live Job, No Pending Candidate'), findsOneWidget);
    // "Applicants Came, None Accepted" appears once for Patients and once for
    // Rehab/Hospitals — both entity types share that exact report title.
    expect(find.text('Applicants Came, None Accepted'), findsNWidgets(2));
    expect(find.text('Patient Activity (Most/Least Active)'), findsOneWidget);
    expect(find.text('No Jobs Posted, Ever'), findsOneWidget);
    expect(find.text('Requirements Posted, No Applicant in N Days'), findsOneWidget);
    expect(find.text('Organisation Activity (Most/Least Active)'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Run'), findsNothing);
  });

  testWidgets('Unassigned or No Duty needs no params and shows results on Run', (tester) async {
    final repo = _FakeAdminReportsRepository(unassignedOrNoDutyResult: [
      {
        'profile_id': 'profile-1',
        'user_id': 'user-1',
        'caregiver_number': 542,
        'full_name': 'Ramesh Kumar',
        'phone': '+919876543210',
        'verification_status': 'pending_call',
        'ever_had_duty': false,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Unassigned or No Duty'));
    await tester.pumpAndSettle();

    expect(find.text('Days'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Run'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(find.text('NUR-542 · Ramesh Kumar'), findsOneWidget);
    expect(find.text('Never had a duty'), findsOneWidget);
  });

  testWidgets('Stalled Duty shows a Days field and sends it to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(stalledDutyResult: [
      {
        'profile_id': 'profile-2',
        'caregiver_number': 543,
        'full_name': 'Sita Devi',
        'phone': '+919876500001',
        'engagement_type': 'job',
        'job_number': 10,
        'admin_job_number': 542,
        'patient_job_number': null,
        'requirement_number': null,
        'accepted_at': '2026-08-01T10:00:00Z',
        'days_since_accepted': 12,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Assigned, Duty Not Completed in N Days'));
    await tester.pumpAndSettle();

    final daysField = find.widgetWithText(TextField, 'Days');
    expect(daysField, findsOneWidget);
    await tester.enterText(daysField, '10');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedStalledDutyDays, 10);
    expect(find.text('NUR-543 · Sita Devi'), findsOneWidget);
    expect(find.textContaining('ADMIN-JOB-542'), findsOneWidget);
    expect(find.textContaining('Accepted 12 days ago'), findsOneWidget);
  });

  testWidgets('More Than X Jobs shows a min-jobs field and sends it to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(overThresholdActiveResult: [
      {
        'profile_id': 'profile-3',
        'caregiver_number': 544,
        'full_name': 'Anita Rao',
        'phone': '+919876500002',
        'accepted_count': 3,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('More Than X Jobs Accepted, Not Completed'));
    await tester.pumpAndSettle();

    final minJobsField = find.widgetWithText(TextField, 'More than X jobs');
    await tester.enterText(minJobsField, '2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedMinJobs, 2);
    expect(find.textContaining('3 accepted jobs, not completed'), findsOneWidget);
  });

  testWidgets('Activity shows Days + Order fields and sends both to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(activityResult: [
      {
        'profile_id': 'profile-4',
        'caregiver_number': 545,
        'full_name': 'Deepak Nair',
        'phone': '+919876500003',
        'activity_count': 5,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Caregiver Activity (Most/Least Active)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Days'), '14');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Least active first').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedActivityDays, 14);
    expect(repo.capturedActivityOrder, 'asc');
    expect(find.textContaining('5 application(s) in the window'), findsOneWidget);
  });

  testWidgets('No Caregiver Applied shows a Days field and sends it to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(patientNoApplicantsResult: [
      {
        'profile_id': 'ind-profile-1',
        'user_id': 'ind-user-1',
        'patient_number': 601,
        'full_name': 'Asha Patel',
        'phone': '+919876500010',
        'job_id': 'job-1',
        'job_number': 20,
        'admin_job_number': null,
        'patient_job_number': 601,
        'job_status': 'active',
        'posted_at': '2026-08-01T10:00:00Z',
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('No Caregiver Applied in N Days'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Days'), '5');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedPatientNoApplicantsDays, 5);
    expect(find.text('PAT-601 · Asha Patel'), findsOneWidget);
    expect(find.textContaining('PAT-JOB-601'), findsOneWidget);
    expect(find.textContaining('No applicants in the window'), findsOneWidget);
  });

  testWidgets('Live Job, No Pending Candidate needs no params and calls the repository on Run', (tester) async {
    final repo = _FakeAdminReportsRepository(patientNoPendingCandidateResult: [
      {
        'profile_id': 'ind-profile-2',
        'user_id': 'ind-user-2',
        'patient_number': 602,
        'full_name': 'Ravi Kumar',
        'phone': '+919876500011',
        'job_id': 'job-2',
        'job_number': 21,
        'admin_job_number': 550,
        'patient_job_number': null,
        'job_status': 'active',
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Live Job, No Pending Candidate'));
    await tester.pumpAndSettle();

    expect(find.text('Days'), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.patientNoPendingCandidateCalled, isTrue);
    expect(find.text('PAT-602 · Ravi Kumar'), findsOneWidget);
    expect(find.textContaining('ADMIN-JOB-550'), findsOneWidget);
    expect(find.textContaining('Nothing pending review'), findsOneWidget);
  });

  testWidgets('Applicants Came, None Accepted needs no params and shows the applicant count', (tester) async {
    final repo = _FakeAdminReportsRepository(patientUnconvertedApplicantsResult: [
      {
        'profile_id': 'ind-profile-3',
        'user_id': 'ind-user-3',
        'patient_number': 603,
        'full_name': 'Meena Iyer',
        'phone': '+919876500012',
        'job_id': 'job-3',
        'job_number': 22,
        'admin_job_number': null,
        'patient_job_number': 603,
        'job_status': 'active',
        'applicant_count': 2,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Applicants Came, None Accepted').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.patientUnconvertedApplicantsCalled, isTrue);
    expect(find.textContaining('2 applicant(s), none accepted'), findsOneWidget);
  });

  testWidgets('Patient Activity shows Days + Order fields and sends both to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(patientActivityResult: [
      {
        'profile_id': 'ind-profile-4',
        'user_id': 'ind-user-4',
        'patient_number': 604,
        'full_name': 'Kabir Singh',
        'phone': '+919876500013',
        'activity_count': 3,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Patient Activity (Most/Least Active)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Days'), '30');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Least active first').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedPatientActivityDays, 30);
    expect(repo.capturedPatientActivityOrder, 'asc');
    expect(find.textContaining('3 job(s) posted in the window'), findsOneWidget);
  });

  testWidgets('tapping a patient result row navigates to /individual-detail with the user id', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeAdminReportsRepository(patientNoPendingCandidateResult: [
      {
        'profile_id': 'ind-profile-5',
        'user_id': 'ind-user-5',
        'patient_number': 605,
        'full_name': 'Divya Menon',
        'phone': '+919876500014',
        'job_id': 'job-5',
        'job_number': 23,
        'admin_job_number': null,
        'patient_job_number': 605,
        'job_status': 'active',
      },
    ]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
          adminReportsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: const ReportsScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Individual Detail Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live Job, No Pending Candidate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PAT-605 · Divya Menon'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/individual-detail');
    expect(pushedArgs, 'ind-user-5');
  });

  testWidgets('shows "No results" when a report returns an empty list', (tester) async {
    await _pump(tester, _FakeAdminReportsRepository());

    await tester.tap(find.text('Unassigned or No Duty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(find.text('No results.'), findsOneWidget);
  });

  testWidgets('rejects Run with an invalid Days value and does not call the repository', (tester) async {
    final repo = _FakeAdminReportsRepository();
    await _pump(tester, repo);

    await tester.tap(find.text('Assigned, Duty Not Completed in N Days'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Days'), 'not-a-number');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedStalledDutyDays, isNull);
    expect(find.text('Enter a valid number of days'), findsOneWidget);
  });

  testWidgets('tapping a result row navigates to /caregiver-detail with the profile id', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeAdminReportsRepository(unassignedOrNoDutyResult: [
      {
        'profile_id': 'profile-9',
        'caregiver_number': 546,
        'full_name': 'Kiran Shetty',
        'phone': '+919876500004',
        'verification_status': 'available',
        'ever_had_duty': true,
      },
    ]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
          adminReportsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: const ReportsScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Caregiver Detail Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unassigned or No Duty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NUR-546 · Kiran Shetty'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/caregiver-detail');
    expect(pushedArgs, 'profile-9');
  });

  testWidgets('No Jobs Posted, Ever needs no params and shows results on Run', (tester) async {
    final repo = _FakeAdminReportsRepository(organisationNoJobsPostedResult: [
      {
        'profile_id': 'org-profile-1',
        'user_id': 'org-user-1',
        'org_number': 701,
        'organisation_name': 'Sunrise Clinic',
        'full_name': 'Dr. Nina Fernandes',
        'phone': '+919876500020',
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('No Jobs Posted, Ever'));
    await tester.pumpAndSettle();

    expect(find.text('Days'), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.organisationNoJobsPostedCalled, isTrue);
    expect(find.text('ORG-701 · Sunrise Clinic'), findsOneWidget);
    expect(find.textContaining('No requirements posted, ever'), findsOneWidget);
  });

  testWidgets('Requirements Posted, No Applicant shows a Days field and sends it to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(organisationNoApplicantsResult: [
      {
        'profile_id': 'org-profile-2',
        'user_id': 'org-user-2',
        'org_number': 702,
        'organisation_name': 'Hopewell Rehab',
        'full_name': 'Suresh Bhat',
        'phone': '+919876500021',
        'live_requirement_count': 2,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Requirements Posted, No Applicant in N Days'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Days'), '5');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedOrganisationNoApplicantsDays, 5);
    expect(find.text('ORG-702 · Hopewell Rehab'), findsOneWidget);
    expect(find.textContaining('2 live requirement(s)'), findsOneWidget);
    expect(find.textContaining('No applicants in the window'), findsOneWidget);
  });

  testWidgets('Applicants Came, None Accepted (Rehab/Hospitals) needs no params and shows the applicant count',
      (tester) async {
    final repo = _FakeAdminReportsRepository(organisationUnconvertedApplicantsResult: [
      {
        'profile_id': 'org-profile-3',
        'user_id': 'org-user-3',
        'org_number': 703,
        'organisation_name': 'Green Valley Hospital',
        'full_name': 'Anil Kapoor',
        'phone': '+919876500022',
        'applicant_count': 4,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Applicants Came, None Accepted').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.organisationUnconvertedApplicantsCalled, isTrue);
    expect(find.textContaining('4 applicant(s), none accepted'), findsOneWidget);
  });

  testWidgets('Organisation Activity shows Days + Order fields and sends both to the repository', (tester) async {
    final repo = _FakeAdminReportsRepository(organisationActivityResult: [
      {
        'profile_id': 'org-profile-4',
        'user_id': 'org-user-4',
        'org_number': 704,
        'organisation_name': 'Lakeside Nursing Home',
        'full_name': 'Priya Menon',
        'phone': '+919876500023',
        'activity_count': 6,
      },
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Organisation Activity (Most/Least Active)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Days'), '30');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Least active first').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    expect(repo.capturedOrganisationActivityDays, 30);
    expect(repo.capturedOrganisationActivityOrder, 'asc');
    expect(find.textContaining('6 requirement(s) posted in the window'), findsOneWidget);
  });

  testWidgets('tapping an organisation result row navigates to /organisation-detail with the user id', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeAdminReportsRepository(organisationNoJobsPostedResult: [
      {
        'profile_id': 'org-profile-5',
        'user_id': 'org-user-5',
        'org_number': 705,
        'organisation_name': 'Harmony Hospice',
        'full_name': 'Vikram Joshi',
        'phone': '+919876500024',
      },
    ]);

    String? pushedRoute;
    Object? pushedArgs;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          sessionProvider.overrideWith(
            (ref) => SessionNotifier(localStorage)
              ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
          ),
          adminReportsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: const ReportsScreen(),
          onGenerateRoute: (settings) {
            pushedRoute = settings.name;
            pushedArgs = settings.arguments;
            return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Organisation Detail Screen')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('No Jobs Posted, Ever'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Run'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ORG-705 · Harmony Hospice'));
    await tester.pumpAndSettle();

    expect(pushedRoute, '/organisation-detail');
    expect(pushedArgs, 'org-user-5');
  });
}
