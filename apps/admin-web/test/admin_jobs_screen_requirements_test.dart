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
import 'package:admin_web/features/jobs/data/admin_jobs_repository.dart';
import 'package:admin_web/features/jobs/screens/admin_jobs_screen.dart';
import 'package:admin_web/features/organisation_requirements/data/admin_organisation_requirements_repository.dart';

/// Organisation-requirement-specific behavior (approve/reject/schedule/
/// applicants/read-only detail), now surfaced through the merged single
/// Jobs tab (AdminJobsScreen) rather than the former standalone
/// AdminOrganisationRequirementsScreen. The jobs side of the merge (list
/// rendering, Posted By filter fetch/skip logic) is covered in
/// admin_jobs_screen_test.dart; this file exercises everything downstream
/// of a requirement row exactly as the old dedicated screen's tests did.
AdminOrganisationRequirement _requirement({
  String id = 'r1',
  int requirementNumber = 101,
  String status = JobStatus.pendingReview,
  String? rejectionReason,
  bool accommodationProvided = true,
  bool foodProvided = false,
  String? typeOfNurseOther,
  int numberOfVacancies = 1,
  String? preferredGender,
  String? durationType = RequirementDuration.shortTerm,
}) {
  return AdminOrganisationRequirement(
    id: id,
    requirementNumber: requirementNumber,
    postedBy: 'org-user-1',
    typeOfNurse: TypeOfNurse.auxiliaryNurse,
    typeOfNurseOther: typeOfNurseOther,
    accommodationProvided: accommodationProvided,
    foodProvided: foodProvided,
    numberOfVacancies: numberOfVacancies,
    preferredGender: preferredGender,
    durationType: durationType,
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

class _FakeAdminOrganisationRequirementsRepository
    extends AdminOrganisationRequirementsRepository {
  List<AdminOrganisationRequirement> items;
  List<OrganisationRequirementApplicationModel> applications;
  String? approvedId;
  String? rejectedId;
  String? rejectedReason;
  String? decidedRequirementId;
  String? decidedApplicationId;
  String? decidedStatus;

  OrganisationRequirementListFilters? lastFilters;

  _FakeAdminOrganisationRequirementsRepository(this.items,
      [this.applications = const []])
      : super(Dio());

  @override
  Future<List<AdminOrganisationRequirement>> list({
    OrganisationRequirementListFilters filters =
        const OrganisationRequirementListFilters(),
  }) async {
    lastFilters = filters;
    return items;
  }

  @override
  Future<
      (
        AdminOrganisationRequirement,
        List<OrganisationRequirementApplicationModel>
      )> getDetail(String id) async {
    final requirement = items.firstWhere((item) => item.id == id);
    return (requirement, applications);
  }

  @override
  Future<void> approve(String id) async {
    approvedId = id;
  }

  @override
  Future<void> reject(String id, String reason) async {
    rejectedId = id;
    rejectedReason = reason;
  }

  @override
  Future<void> decideApplication(
      String requirementId, String applicationId, String status) async {
    decidedRequirementId = requirementId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
  }
}

/// The merged screen always fetches jobs too on load — an empty fake avoids
/// a real Dio() call, since this file only exercises the requirements side.
class _FakeEmptyAdminJobsRepository extends AdminJobsRepository {
  _FakeEmptyAdminJobsRepository() : super(Dio());

  @override
  Future<List<JobModel>> list(
          {JobListFilters filters = const JobListFilters()}) async =>
      [];

  @override
  Future<List<JobPosterOption>> listPosters() async => [];
}

Future<void> _selectFilterDropdown(
    WidgetTester tester, String fieldLabel, String optionLabel) async {
  final field =
      find.widgetWithText(DropdownButtonFormField<String?>, fieldLabel).first;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester,
    _FakeAdminOrganisationRequirementsRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        adminJobsRepositoryProvider
            .overrideWithValue(_FakeEmptyAdminJobsRepository()),
        adminOrganisationRequirementsRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state =
                AdminSessionAuthenticated(userId: 'admin-1', role: 'admin'),
        ),
      ],
      child: const MaterialApp(home: AdminJobsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'lists requirements with requirement number, status, and org name',
      (tester) async {
    await _pump(
        tester, _FakeAdminOrganisationRequirementsRepository([_requirement()]));

    expect(find.text('ORG-JOB-101'), findsOneWidget);
    expect(find.text('Pending Review'), findsOneWidget);
    expect(find.text('City Rehab Center'), findsOneWidget);
  });

  testWidgets('shows the rejection reason for a rejected requirement',
      (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(
            status: JobStatus.closed, rejectionReason: 'Incomplete details'),
      ]),
    );

    expect(find.text('Reason: Incomplete details'), findsOneWidget);
  });

  testWidgets(
      'Approve and Reject only show for a pending_review requirement; nothing to edit once active',
      (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(status: JobStatus.active),
      ]),
    );

    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Applicants'), findsOneWidget);
  });

  testWidgets(
      'approving a pending_review requirement is a bare click — no fields to fill in',
      (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Approve ORG-JOB-101'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(repo.approvedId, 'r1');
  });

  testWidgets('rejecting requires a reason before Confirm is enabled',
      (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    final confirmButton = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Missing accommodation details');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(repo.rejectedId, 'r1');
    expect(repo.rejectedReason, 'Missing accommodation details');
  });

  testWidgets(
      'Applicants dialog shows Accept/Reject for an applied application and calls decideApplication',
      (
    tester,
  ) async {
    final repo = _FakeAdminOrganisationRequirementsRepository(
      [
        _requirement(status: JobStatus.active)
      ],
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

  testWidgets(
      'Applicants dialog shows a Profile button for every applicant, decided or not',
      (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository(
      [
        _requirement(status: JobStatus.active)
      ],
      [_application(status: JobApplicationStatus.accepted)],
    );
    await _pump(tester, repo);

    await tester.tap(find.text('Applicants'));
    await tester.pumpAndSettle();

    expect(find.text('Nurse Nita'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Profile'), findsOneWidget);
  });

  testWidgets(
      'Applicants dialog shows no actions for an already-decided application',
      (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository(
      [
        _requirement(status: JobStatus.active)
      ],
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

  testWidgets(
      'tapping an active requirement row opens a read-only detail view with no Approve action',
      (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([
        _requirement(status: JobStatus.active),
      ]),
    );

    await tester.tap(find.text('ORG-JOB-101'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Type of Nurse')),
        findsOneWidget);
    expect(
        find.descendant(
            of: dialog, matching: find.widgetWithText(ElevatedButton, 'Approve')),
        findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('Close')),
        findsOneWidget);
  });

  testWidgets(
      'tapping Approve inside a pending_review requirement\'s read-only detail view opens the approve confirmation',
      (tester) async {
    await _pump(
      tester,
      _FakeAdminOrganisationRequirementsRepository([_requirement()]),
    );

    await tester.tap(find.text('ORG-JOB-101'));
    await tester.pumpAndSettle();

    final readOnlyDialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(
        of: readOnlyDialog,
        matching: find.widgetWithText(ElevatedButton, 'Approve')));
    await tester.pumpAndSettle();

    expect(find.text('Approve ORG-JOB-101'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
      'picking "Hospital" under Posted By and entering a search term passes both through to the '
      'organisation requirements fetch', (tester) async {
    final repo = _FakeAdminOrganisationRequirementsRepository([_requirement()]);
    await _pump(tester, repo);

    await tester.enterText(
      find.widgetWithText(
          TextField, 'Search job ID or patient ID (e.g. PAT-501)'),
      'ORG-JOB-101',
    );
    await _selectFilterDropdown(tester, 'Status', 'Active');
    await _selectFilterDropdown(tester, 'Posted By', 'Hospital');
    await _selectFilterDropdown(tester, 'City', 'Bangalore');
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(repo.lastFilters?.search, 'ORG-JOB-101');
    expect(repo.lastFilters?.status, 'active');
    expect(repo.lastFilters?.organisationType, 'hospital');
    expect(repo.lastFilters?.city, 'bangalore');
  });
}
