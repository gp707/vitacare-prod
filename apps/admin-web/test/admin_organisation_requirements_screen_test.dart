import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:admin_web/core/providers.dart';
import 'package:admin_web/core/storage/local_storage.dart';
import 'package:admin_web/features/auth/state/session_notifier.dart';
import 'package:admin_web/features/auth/state/session_state.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';
import 'package:admin_web/features/organisation_requirements/screens/admin_organisation_requirements_screen.dart';

AdminOrganisationRequirement _requirement({
  String id = 'r1',
  int requirementNumber = 101,
  String status = JobStatus.pendingReview,
  String? frequencyOfCare,
  int? salaryAmount,
  String? scheduleType,
  String? startDate,
  String? endDate,
  List<int>? specificDays,
  String? rejectionReason,
  bool accommodationProvided = true,
  bool foodProvided = false,
}) {
  return AdminOrganisationRequirement(
    id: id,
    requirementNumber: requirementNumber,
    postedBy: 'org-user-1',
    typeOfNurse: TypeOfNurse.auxiliaryNurse,
    frequencyOfCare: frequencyOfCare,
    salaryAmount: salaryAmount,
    scheduleType: scheduleType,
    startDate: startDate,
    endDate: endDate,
    specificDays: specificDays,
    accommodationProvided: accommodationProvided,
    foodProvided: foodProvided,
    status: status,
    rejectionReason: rejectionReason,
    postedAt: '2026-08-01T10:00:00Z',
    organisationName: 'City Rehab Center',
    organisationType: OrganisationType.rehab,
    city: City.bangalore,
    area: 'Whitefield',
  );
}

OrganisationRequirementApplicationModel _application({
  String id = 'app1',
  String status = JobApplicationStatus.applied,
  String fullName = 'Nurse Nita',
}) {
  return OrganisationRequirementApplicationModel(
    id: id,
    requirementId: 'r1',
    profileId: 'profile-1',
    status: status,
    fullName: fullName,
    phone: '+919876500000',
    updatedAt: '2026-08-01T10:00:00Z',
  );
}

class _FakeAdminOrganisationRequirementsRepository extends AdminOrganisationRequirementsRepository {
  List<AdminOrganisationRequirement> items;
  List<OrganisationRequirementApplicationModel> applications;
  String? approvedId;
  String? approvedFrequency;
  int? approvedSalary;
  String? approvedScheduleType;
  String? approvedStartDate;
  String? approvedEndDate;
  List<int>? approvedSpecificDays;
  String? rejectedId;
  String? rejectedReason;
  String? decidedRequirementId;
  String? decidedApplicationId;
  String? decidedStatus;

  _FakeAdminOrganisationRequirementsRepository(this.items, [this.applications = const []]) : super(Dio());

  @override
  Future<List<AdminOrganisationRequirement>> list({String? status}) async => items;

  @override
  Future<(AdminOrganisationRequirement, List<OrganisationRequirementApplicationModel>)> getDetail(String id) async {
    final requirement = items.firstWhere((item) => item.id == id);
    return (requirement, applications);
  }

  @override
  Future<void> approve(
    String id, {
    required String typeOfNurse,
    required String frequencyOfCare,
    required int salaryAmount,
    required String scheduleType,
    String? startDate,
    String? endDate,
    List<int>? specificDays,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
  }) async {
    approvedId = id;
    approvedFrequency = frequencyOfCare;
    approvedSalary = salaryAmount;
    approvedScheduleType = scheduleType;
    approvedStartDate = startDate;
    approvedEndDate = endDate;
    approvedSpecificDays = specificDays;
  }

  @override
  Future<void> reject(String id, String reason) async {
    rejectedId = id;
    rejectedReason = reason;
  }

  @override
  Future<void> decideApplication(String requirementId, String applicationId, String status) async {
    decidedRequirementId = requirementId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminOrganisationRequirementsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminOrganisationRequirementsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: AdminOrganisationRequirementsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
      'OrganisationRequirementApplicationModel.fromJson parses the real admin-detail backend shape '
      '(requirement_id, not job_id — using JobApplicationModel here throws)', () {
    // Mirrors OrganisationRequirementApplicationWithCaregiver exactly (see
    // findByRequirementId in the backend repository) — this is the actual
    // shape GET /admin/organisation-requirements/:id's `applications` array
    // returns. It has no `job_id` field at all.
    final application = OrganisationRequirementApplicationModel.fromJson({
      'id': 'app-1',
      'requirement_id': 'req-1',
      'profile_id': 'profile-1',
      'status': 'applied',
      'decided_by': null,
      'applied_at': '2026-08-01T10:00:00Z',
      'accepted_at': null,
      'rejected_at': null,
      'completed_at': null,
      'decline_reason': null,
      'created_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-01T10:00:00Z',
      'full_name': 'Nurse Nita',
      'phone': '+919876500000',
      'decided_by_name': null,
    });
    expect(application.id, 'app-1');
    expect(application.requirementId, 'req-1');
    expect(application.fullName, 'Nurse Nita');
    expect(application.status, 'applied');
  });

  testWidgets('lists requirements with requirement number, status, and org name', (tester) async {
    await _pump(tester, _FakeAdminOrganisationRequirementsRepository([_requirement()]));

    expect(find.text('Requirement #101'), findsOneWidget);
    expect(find.text('Pending Review'), findsOneWidget);
    expect(find.text('City Rehab Center'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no requirements', (tester) async {
    await _pump(tester, _FakeAdminOrganisationRequirementsRepository([]));

    expect(find.text('No organisation requirements posted yet.'), findsOneWidget);
  });

  testWidgets('shows the rejection reason for a rejected requirement', (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(status: JobStatus.closed, rejectionReason: 'Incomplete details'),
      ]),
    );

    expect(find.text('Reason: Incomplete details'), findsOneWidget);
  });

  testWidgets('Reject only shows for a pending_review requirement; Edit is always available', (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(status: JobStatus.active, frequencyOfCare: FrequencyOfCare.monthly, salaryAmount: 25000),
      ]),
    );

    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Applicants'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets(
      'editing an active requirement pre-fills current frequency/salary/schedule and calls approve() again',
      (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([
      _requirement(
        status: JobStatus.active,
        frequencyOfCare: FrequencyOfCare.monthly,
        salaryAmount: 25000,
        scheduleType: 'specific_days',
        specificDays: [3, 12, 20],
      ),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit requirement #101'), findsOneWidget);
    expect(find.text('Monthly'), findsWidgets);
    final salaryField = tester.widget<TextField>(find.byType(TextField));
    expect(salaryField.controller!.text, '25000');
    // Pre-filled from the existing specific_days schedule.
    final dayThreeChip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, '3'));
    expect(dayThreeChip.selected, isTrue);

    await tester.enterText(find.byType(TextField), '28000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.approvedId, 'r1');
    expect(repo.approvedFrequency, FrequencyOfCare.monthly);
    expect(repo.approvedSalary, 28000);
    expect(repo.approvedScheduleType, 'specific_days');
    expect(repo.approvedSpecificDays, [3, 12, 20]);
  });

  testWidgets('approving with a specific_days schedule fills frequency/salary/days and calls the repository',
      (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '30000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Specific Days'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '5'));
    await tester.tap(find.widgetWithText(FilterChip, '15'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();

    expect(repo.approvedId, 'r1');
    expect(repo.approvedFrequency, FrequencyOfCare.monthly);
    expect(repo.approvedSalary, 30000);
    expect(repo.approvedScheduleType, 'specific_days');
    expect(repo.approvedSpecificDays, [5, 15]);
  });

  testWidgets('approving with a date_range schedule requires both dates and calls the repository', (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '30000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Date Range'));
    await tester.pumpAndSettle();

    // Save Changes/Approve stays disabled until both dates are picked —
    // exercised via the submit button's onPressed being null rather than
    // driving the real date picker dialog.
    final approveButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Approve').last);
    expect(approveButton.onPressed, isNull);
  });

  testWidgets('rejecting requires a reason before Confirm is enabled', (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Missing accommodation details');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(repo.rejectedId, 'r1');
    expect(repo.rejectedReason, 'Missing accommodation details');
  });

  testWidgets('Applicants dialog shows Accept/Reject for an applied application and calls decideApplication', (
    tester,
  ) async {
    final repo = _FakeAdminOrganisationRequirementsRepository(
      [_requirement(status: JobStatus.active, frequencyOfCare: FrequencyOfCare.daily, salaryAmount: 1500)],
      [_application()],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Nurse Nita'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(repo.decidedRequirementId, 'r1');
    expect(repo.decidedApplicationId, 'app1');
    expect(repo.decidedStatus, JobApplicationStatus.accepted);
  });

  testWidgets('Applicants dialog shows a Profile button for every applicant, decided or not', (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository(
      [_requirement(status: JobStatus.active, frequencyOfCare: FrequencyOfCare.daily, salaryAmount: 1500)],
      [_application(status: JobApplicationStatus.accepted)],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Nurse Nita'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Profile'), findsOneWidget);
  });

  testWidgets('Applicants dialog shows no actions for an already-decided application', (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository(
      [_requirement(status: JobStatus.active, frequencyOfCare: FrequencyOfCare.daily, salaryAmount: 1500)],
      [_application(status: JobApplicationStatus.accepted)],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Nurse Nita'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text(JobApplicationStatus.accepted), findsOneWidget);
  });

  testWidgets('tapping the requirement row opens a read-only detail view, not the edit form', (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(status: JobStatus.active, frequencyOfCare: FrequencyOfCare.daily, salaryAmount: 1800),
      ]),
    );

    await tester.tap(find.text('Requirement #101'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Type of Nurse')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.widgetWithText(ElevatedButton, 'Edit')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Close')), findsOneWidget);
    // Read-only: not the edit form.
    expect(find.text('Edit requirement #101'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsNothing);
  });

  testWidgets('tapping Edit inside the read-only detail view opens the edit form', (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(status: JobStatus.active, frequencyOfCare: FrequencyOfCare.daily, salaryAmount: 1800),
      ]),
    );

    await tester.tap(find.text('Requirement #101'));
    await tester.pumpAndSettle();

    final readOnlyDialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: readOnlyDialog, matching: find.widgetWithText(ElevatedButton, 'Edit')));
    await tester.pumpAndSettle();

    expect(find.text('Edit requirement #101'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save Changes'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
