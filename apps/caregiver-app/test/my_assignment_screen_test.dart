import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:caregiver_app/core/caregiver_messages/caregiver_messages_repository.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/my_assignment_screen.dart';
import 'package:caregiver_app/features/organisation_openings/data/organisation_openings_repository.dart';

class _FakeCaregiverMessagesRepository extends CaregiverMessagesRepository {
  _FakeCaregiverMessagesRepository() : super(Dio());

  @override
  Future<List<CaregiverMessageModel>> get() async => const [];
}

JobModel _assignedJob({
  String id = 'job-1',
  int adminJobNumber = 542,
  String applicationStatus = 'accepted',
  String acceptedAt = '2026-08-02T10:00:00Z',
  String? closeReason,
}) {
  return JobModel.fromJson({
    'id': id,
    'admin_job_number': adminJobNumber,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver for an elderly patient',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'languages': ['hindi'],
    'salary_amount': '30000',
    'preferred_gender': 'female',
    'status': 'closed',
    'posted_by': 'admin-1',
    'posted_at': DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'my_application': {
      'status': applicationStatus,
      'applied_at': '2026-08-01T10:00:00Z',
      'accepted_at': acceptedAt,
      'rejected_at': null,
      'completed_at': applicationStatus == 'completed' ? '2026-08-03T10:00:00Z' : null,
      'decided_by_admin': true,
      'close_reason': applicationStatus == 'completed' ? (closeReason ?? 'no_reason') : null,
    },
    'care_receiver': {
      'id': 'cr-1',
      'age': 78,
      'gender': 'female',
      'weight_kg': 60,
      'feeding_type': 'oral_feeding',
      'has_medical_condition': false,
      'medical_conditions': [],
      'toilet_assistance': ['independent'],
      'requires_vital_monitoring': false,
      'vital_monitoring_types': [],
    },
    'job_poster': {
      'full_name': 'Admin Kumar',
      'phone': '+919876500000',
    },
  });
}

OrganisationRequirementModel _assignedRequirement({
  String id = 'req-1',
  int requirementNumber = 7,
  String applicationStatus = 'accepted',
  String acceptedAt = '2026-08-04T10:00:00Z',
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Post-surgery wound care',
    'number_of_vacancies': 1,
    'status': 'closed',
    'posted_at': '2026-08-01T10:00:00Z',
    'organisation_name': 'City Hospital',
    'organisation_type': 'hospital',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'organisation_phone': '+919876511111',
    'duration_type': 'long_term',
    'preferred_gender': 'female',
    'my_application': {
      'status': applicationStatus,
      'applied_at': '2026-08-03T10:00:00Z',
      'accepted_at': acceptedAt,
      'rejected_at': null,
      'completed_at': applicationStatus == 'completed' ? '2026-08-05T10:00:00Z' : null,
      'decided_by_admin': true,
    },
  });
}

class _FakeJobsRepository extends JobsRepository {
  List<JobModel> jobs;
  String? completedJobId;
  String? completedCloseReason;
  bool completeStillAssigned;
  _FakeJobsRepository([this.jobs = const [], this.completeStillAssigned = false]) : super(Dio());

  @override
  Future<List<JobModel>> listActiveJobs() async => const [];

  @override
  Future<List<JobModel>> getAssignedJobs() async => jobs;

  @override
  Future<bool> completeJob(String jobId, {String? closeReason}) async {
    completedJobId = jobId;
    completedCloseReason = closeReason;
    jobs = jobs
        .map((j) => j.id == jobId
            ? _assignedJob(id: j.id, adminJobNumber: j.adminJobNumber!, applicationStatus: 'completed')
            : j)
        .toList();
    return completeStillAssigned;
  }
}

class _FakeOrganisationOpeningsRepository extends OrganisationOpeningsRepository {
  List<OrganisationRequirementModel> requirements;
  String? completedRequirementId;
  String? completedCloseReason;
  String completeReturnsVerificationStatus;
  _FakeOrganisationOpeningsRepository([
    this.requirements = const [],
    this.completeReturnsVerificationStatus = 'available',
  ]) : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> getAssigned() async => requirements;

  @override
  Future<String> complete(String requirementId, {String? closeReason}) async {
    completedRequirementId = requirementId;
    completedCloseReason = closeReason;
    requirements = requirements
        .map((r) => r.id == requirementId
            ? _assignedRequirement(id: r.id, requirementNumber: r.requirementNumber, applicationStatus: 'completed')
            : r)
        .toList();
    return completeReturnsVerificationStatus;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  _FakeJobsRepository? jobsRepo,
  _FakeOrganisationOpeningsRepository? orgRepo,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jobsRepositoryProvider.overrideWithValue(jobsRepo ?? _FakeJobsRepository()),
        organisationOpeningsRepositoryProvider.overrideWithValue(orgRepo ?? _FakeOrganisationOpeningsRepository()),
        localStorageProvider.overrideWithValue(localStorage),
        caregiverMessagesRepositoryProvider.overrideWithValue(_FakeCaregiverMessagesRepository()),
      ],
      child: const MaterialApp(home: MyAssignmentScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

// "Hide completed jobs" defaults on — tests exercising completed card
// content must turn it off first to reveal them.
Future<void> _showCompletedJobs(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(SwitchListTile, 'Hide completed jobs'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the assigned job details, including care receiver', (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob()]));

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);

    // Poster contact info and actions live on the assigned card itself, not
    // inside JobDetailCard's full-screen detail view.
    expect(find.text('Admin Kumar'), findsOneWidget);
    expect(find.text('+919876500000'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsOneWidget);

    // JobDetailCard's About Patient/Requirement detail lives on the
    // full-screen detail view — open it to check the care receiver's info
    // renders.
    await tester.tap(find.text('View Full Details about Patient Requirements'));
    await tester.pumpAndSettle();

    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('78 yrs'), findsOneWidget);
  });

  testWidgets('shows the full action timeline (applied, accepted) on an accepted job in MyJobs', (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob()]));

    expect(find.textContaining('Applied by you:'), findsOneWidget);
    expect(find.textContaining('Accepted by employer:'), findsOneWidget);
  });

  testWidgets('shows "Closed by you" in the timeline once the job is completed, with the close reason underneath',
      (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob(applicationStatus: 'completed')]));
    await _showCompletedJobs(tester);

    expect(find.textContaining('Closed by you:'), findsOneWidget);
    // Defaults to "No Reason" when the fixture doesn't specify one — same
    // default the backend applies when the caregiver doesn't pick anything.
    expect(find.textContaining('Reason: No Reason'), findsOneWidget);
  });

  testWidgets('shows a specific close reason in the timeline when one was given', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([_assignedJob(applicationStatus: 'completed', closeReason: 'duty_complete')]),
    );
    await _showCompletedJobs(tester);

    expect(find.textContaining('Reason: Duty Complete'), findsOneWidget);
  });

  testWidgets("shows an empty state when there are no accepted jobs or requirements", (tester) async {
    await _pump(tester);

    expect(find.text("You don't have any accepted jobs yet."), findsOneWidget);
  });

  testWidgets('lists every accepted/completed job — a caregiver can hold more than one at once', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([
        _assignedJob(id: 'job-1', adminJobNumber: 542, applicationStatus: 'accepted'),
        _assignedJob(id: 'job-2', adminJobNumber: 543, applicationStatus: 'completed'),
      ]),
    );
    await _showCompletedJobs(tester);

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('Job Id: ADMIN-JOB-543'), findsOneWidget);
    // Only the accepted job gets the action button; the completed one shows a badge instead.
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsOneWidget);
    expect(find.text('You closed this job — work completed'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);
  });

  testWidgets(
      'once closed, the poster\'s phone number and Call/WhatsApp actions disappear, but the name stays',
      (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([
        _assignedJob(id: 'job-1', adminJobNumber: 542, applicationStatus: 'accepted'),
        _assignedJob(id: 'job-2', adminJobNumber: 543, applicationStatus: 'completed'),
      ]),
    );
    await _showCompletedJobs(tester);

    // Both cards show the same fixture poster ("Admin Kumar") — the name
    // appears on both, but the phone/actions only on the still-accepted one.
    expect(find.text('Admin Kumar'), findsNWidgets(2));
    expect(find.text('+919876500000'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget);
  });

  testWidgets('does not show the "Hide completed jobs" toggle when there are no completed jobs', (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob()]));

    expect(find.text('Hide completed jobs'), findsNothing);
  });

  testWidgets(
      'defaults to hiding completed cards but keeps accepted ones, and toggling reveals/re-hides them',
      (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([
        _assignedJob(id: 'job-1', adminJobNumber: 542, applicationStatus: 'accepted'),
        _assignedJob(id: 'job-2', adminJobNumber: 543, applicationStatus: 'completed'),
      ]),
    );

    final toggle = find.widgetWithText(SwitchListTile, 'Hide completed jobs');
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue, reason: 'on by default');
    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('Job Id: ADMIN-JOB-543'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('Job Id: ADMIN-JOB-543'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('Job Id: ADMIN-JOB-543'), findsNothing);
  });

  testWidgets('shows a message instead of the empty state when every job is completed and hidden', (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob(applicationStatus: 'completed')]));

    // "Hide completed jobs" is already on by default — no tap needed.

    expect(find.text("You don't have any accepted jobs yet."), findsNothing);
    expect(find.textContaining('are completed and hidden'), findsOneWidget);
  });

  testWidgets('tapping Close Duty, confirming, calls completeJob and refreshes the list', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    // Confirmation dialog appears first — tapping outside/Cancel wouldn't call the API.
    expect(find.text('Close this job?'), findsOneWidget);
    // Reason dropdown defaults to "No Reason" — confirming without
    // touching it still submits an explicit reason.
    expect(find.text('No Reason'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedJobId, 'job-1');
    expect(fakeRepo.completedCloseReason, 'no_reason');
    // Now completed — hidden by default; reveal it to check the resulting
    // badge/button state.
    await _showCompletedJobs(tester);
    expect(find.text('You closed this job — work completed'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsNothing);
  });

  testWidgets('picking a specific reason before confirming Close Duty submits that reason', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'No Reason'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duty Complete').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedCloseReason, 'duty_complete');
  });

  testWidgets('cancelling the confirmation dialog does not call completeJob', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Duty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedJobId, isNull);
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsOneWidget);
  });

  testWidgets('shows a snackbar mentioning availability when completing the last accepted job', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()], false);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Duty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    expect(find.textContaining("now available for new jobs"), findsOneWidget);
  });

  // --- Merged organisation requirements ---

  testWidgets('shows an assigned organisation requirement alongside assigned jobs — no separate tab',
      (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([_assignedJob()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement()]),
    );

    expect(find.text('Job Id: ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ORG-JOB-7'), findsOneWidget);
    // Appears twice — once as the card's own header, once again in its
    // organisation contact card's "Posted by" name line.
    expect(find.text('City Hospital'), findsNWidgets(2));
    expect(find.text('You were accepted for this requirement'), findsOneWidget);
    // Both the job's and the requirement's own action button share the same
    // "Close Duty" label — one per card.
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsNWidgets(2));
  });

  testWidgets('shows the full requirement detail (tags + special skills) on an assigned requirement, same as '
      'the browse-list card', (tester) async {
    await _pump(
      tester,
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement()]),
    );

    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Vacancies: 1'), findsOneWidget);
    expect(find.text('Long Term'), findsOneWidget);
    expect(find.text('Preferred: Female'), findsOneWidget);
    expect(find.text('Post-surgery wound care'), findsOneWidget);
  });

  testWidgets('shows the organisation\'s own contact card (name, phone, Call/WhatsApp) once accepted',
      (tester) async {
    await _pump(
      tester,
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement()]),
    );

    expect(find.text('City Hospital'), findsWidgets);
    expect(find.text('+919876511111'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget);
  });

  testWidgets(
      'once the requirement is closed, the organisation\'s phone number and Call/WhatsApp actions disappear, '
      'but the name stays', (tester) async {
    await _pump(
      tester,
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement(applicationStatus: 'completed')]),
    );
    await _showCompletedJobs(tester);

    expect(find.text('City Hospital'), findsWidgets);
    expect(find.text('+919876511111'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsNothing);
  });

  testWidgets(
      'assigned job and requirement cards each have a bold red border on a light green shade — still active, '
      'not yet closed', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([_assignedJob()]),
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement()]),
    );

    for (final anchor in ['Job Id: ADMIN-JOB-542', 'ORG-JOB-7']) {
      final container = tester.widget<Container>(
        find.ancestor(of: find.text(anchor), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.width, greaterThanOrEqualTo(2.5));
      expect(border.top.color, AppColors.error);
      expect(decoration.color, AppColors.success.withValues(alpha: 0.06));
    }
  });

  testWidgets('a completed assigned job card has a grey border instead — no longer active', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([_assignedJob(applicationStatus: 'completed')]),
    );
    await _showCompletedJobs(tester);

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Job Id: ADMIN-JOB-542'), matching: find.byType(Container)).first,
    );
    final border = (container.decoration as BoxDecoration).border as Border;
    expect(border.top.color, AppColors.textSecondary);
  });

  testWidgets('sorts assigned jobs and requirements together by accepted date, newest first', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([_assignedJob(acceptedAt: '2026-08-10T10:00:00Z')]),
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement(acceptedAt: '2026-08-01T10:00:00Z')]),
    );

    final jobCenter = tester.getCenter(find.text('Job Id: ADMIN-JOB-542'));
    final requirementCenter = tester.getCenter(find.text('ORG-JOB-7'));
    expect(jobCenter.dy, lessThan(requirementCenter.dy));
  });

  testWidgets('a completed requirement shows a badge instead of the action button', (tester) async {
    await _pump(
      tester,
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement(applicationStatus: 'completed')]),
    );
    await _showCompletedJobs(tester);

    expect(find.text('You closed this requirement — work completed'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsNothing);
  });

  testWidgets(
      'tapping Close Duty on a requirement, confirming, calls complete() and refreshes the list',
      (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository([_assignedRequirement()]);
    await _pump(tester, orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    expect(find.text('Close this requirement?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    expect(orgRepo.completedRequirementId, 'req-1');
    await _showCompletedJobs(tester);
    expect(find.text('You closed this requirement — work completed'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Duty'), findsNothing);
  });

  testWidgets('shows a snackbar mentioning availability when completing the last accepted requirement',
      (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository(
      [_assignedRequirement()],
      'available',
    );
    await _pump(tester, orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Duty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Duty'));
    await tester.pumpAndSettle();

    expect(find.textContaining("now available for new jobs"), findsOneWidget);
  });
}
