import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/my_assignment_screen.dart';
import 'package:caregiver_app/features/organisation_openings/data/organisation_openings_repository.dart';

JobModel _assignedJob({
  String id = 'job-1',
  int jobNumber = 42,
  String applicationStatus = 'accepted',
  String acceptedAt = '2026-08-02T10:00:00Z',
}) {
  return JobModel.fromJson({
    'id': id,
    'job_number': jobNumber,
    'admin_job_number': jobNumber + 500,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver for an elderly patient',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'languages': ['hindi'],
    'salary_amount': 30000,
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
    },
    'care_receiver': {
      'id': 'cr-1',
      'age': 78,
      'gender': 'female',
      'weight_kg': 60,
      'mobility': 'uses_wheelchair',
      'communication': 'verbal',
      'feeding_type': 'oral_needs_assistance',
      'medical_assistance': ['medication_reminders'],
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
  String? scheduleType,
  String? startDate,
  String? endDate,
  String? scheduleRepeat,
  List<int>? specificDays,
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'frequency_of_care': 'monthly',
    'salary_amount': 40000,
    'schedule_type': scheduleType,
    'start_date': startDate,
    'end_date': endDate,
    'schedule_repeat': scheduleRepeat,
    'specific_days': specificDays,
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Post-surgery wound care',
    'status': 'closed',
    'posted_at': '2026-08-01T10:00:00Z',
    'organisation_name': 'City Hospital',
    'organisation_type': 'hospital',
    'city': 'bangalore',
    'area': 'Indiranagar',
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
  bool completeStillAssigned;
  _FakeJobsRepository([this.jobs = const [], this.completeStillAssigned = false]) : super(Dio());

  @override
  Future<List<JobModel>> getAssignedJobs() async => jobs;

  @override
  Future<bool> completeJob(String jobId) async {
    completedJobId = jobId;
    jobs = jobs
        .map((j) => j.id == jobId ? _assignedJob(id: j.id, jobNumber: j.jobNumber, applicationStatus: 'completed') : j)
        .toList();
    return completeStillAssigned;
  }
}

class _FakeOrganisationOpeningsRepository extends OrganisationOpeningsRepository {
  List<OrganisationRequirementModel> requirements;
  String? completedRequirementId;
  String completeReturnsVerificationStatus;
  _FakeOrganisationOpeningsRepository([
    this.requirements = const [],
    this.completeReturnsVerificationStatus = 'available',
  ]) : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> getAssigned() async => requirements;

  @override
  Future<String> complete(String requirementId) async {
    completedRequirementId = requirementId;
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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jobsRepositoryProvider.overrideWithValue(jobsRepo ?? _FakeJobsRepository()),
        organisationOpeningsRepositoryProvider.overrideWithValue(orgRepo ?? _FakeOrganisationOpeningsRepository()),
      ],
      child: const MaterialApp(home: MyAssignmentScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the assigned job details, including care receiver', (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob()]));

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);

    // JobDetailCard's About Patient/Requirement detail is collapsed by
    // default — expand it to check the care receiver's info renders.
    await tester.tap(find.text('Show details'));
    await tester.pumpAndSettle();

    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('78 yrs'), findsOneWidget);
    expect(find.text('Admin Kumar'), findsOneWidget);
    expect(find.text('+919876500000'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Job'), findsOneWidget);
  });

  testWidgets("shows an empty state when there are no accepted jobs or requirements", (tester) async {
    await _pump(tester);

    expect(find.text("You don't have any accepted jobs yet."), findsOneWidget);
  });

  testWidgets('lists every accepted/completed job — a caregiver can hold more than one at once', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([
        _assignedJob(id: 'job-1', jobNumber: 42, applicationStatus: 'accepted'),
        _assignedJob(id: 'job-2', jobNumber: 43, applicationStatus: 'completed'),
      ]),
    );

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ADMIN-JOB-543'), findsOneWidget);
    // Only the accepted job gets the action button; the completed one shows a badge instead.
    expect(find.widgetWithText(OutlinedButton, 'Close Job'), findsOneWidget);
    expect(find.text('You closed this job'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);
  });

  testWidgets(
      'once closed, the poster\'s phone number and Call/WhatsApp actions disappear, but the name stays',
      (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([
        _assignedJob(id: 'job-1', jobNumber: 42, applicationStatus: 'accepted'),
        _assignedJob(id: 'job-2', jobNumber: 43, applicationStatus: 'completed'),
      ]),
    );

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

  testWidgets('toggling "Hide completed jobs" hides completed cards but keeps accepted ones, and can be undone',
      (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([
        _assignedJob(id: 'job-1', jobNumber: 42, applicationStatus: 'accepted'),
        _assignedJob(id: 'job-2', jobNumber: 43, applicationStatus: 'completed'),
      ]),
    );

    final toggle = find.widgetWithText(SwitchListTile, 'Hide completed jobs');
    expect(toggle, findsOneWidget);
    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ADMIN-JOB-543'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ADMIN-JOB-543'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ADMIN-JOB-543'), findsOneWidget);
  });

  testWidgets('shows a message instead of the empty state when every job is completed and hidden', (tester) async {
    await _pump(tester, jobsRepo: _FakeJobsRepository([_assignedJob(applicationStatus: 'completed')]));

    await tester.tap(find.widgetWithText(SwitchListTile, 'Hide completed jobs'));
    await tester.pumpAndSettle();

    expect(find.text("You don't have any accepted jobs yet."), findsNothing);
    expect(find.textContaining('are completed and hidden'), findsOneWidget);
  });

  testWidgets('tapping Close Job, confirming, calls completeJob and refreshes the list', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Job'));
    await tester.pumpAndSettle();

    // Confirmation dialog appears first — tapping outside/Cancel wouldn't call the API.
    expect(find.text('Close this job?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Job'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedJobId, 'job-1');
    expect(find.text('You closed this job'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Job'), findsNothing);
  });

  testWidgets('cancelling the confirmation dialog does not call completeJob', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedJobId, isNull);
    expect(find.widgetWithText(OutlinedButton, 'Close Job'), findsOneWidget);
  });

  testWidgets('shows a snackbar mentioning availability when completing the last accepted job', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()], false);
    await _pump(tester, jobsRepo: fakeRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Job'));
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

    expect(find.text('ADMIN-JOB-542'), findsOneWidget);
    expect(find.text('ORG-JOB-7'), findsOneWidget);
    expect(find.text('City Hospital'), findsOneWidget);
    expect(find.text('You were accepted for this requirement'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Job'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Requirement'), findsOneWidget);
  });

  testWidgets('sorts assigned jobs and requirements together by accepted date, oldest first', (tester) async {
    await _pump(
      tester,
      jobsRepo: _FakeJobsRepository([_assignedJob(acceptedAt: '2026-08-10T10:00:00Z')]),
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement(acceptedAt: '2026-08-01T10:00:00Z')]),
    );

    final jobCenter = tester.getCenter(find.text('ADMIN-JOB-542'));
    final requirementCenter = tester.getCenter(find.text('ORG-JOB-7'));
    expect(requirementCenter.dy, lessThan(jobCenter.dy));
  });

  testWidgets('a completed requirement shows a badge instead of the action button', (tester) async {
    await _pump(
      tester,
      orgRepo: _FakeOrganisationOpeningsRepository([_assignedRequirement(applicationStatus: 'completed')]),
    );

    expect(find.text('You closed this requirement'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Requirement'), findsNothing);
  });

  testWidgets(
      'tapping Close Requirement on a requirement, confirming, calls complete() and refreshes the list',
      (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository([_assignedRequirement()]);
    await _pump(tester, orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Close this requirement?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Requirement'));
    await tester.pumpAndSettle();

    expect(orgRepo.completedRequirementId, 'req-1');
    expect(find.text('You closed this requirement'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Close Requirement'), findsNothing);
  });

  testWidgets('shows a snackbar mentioning availability when completing the last accepted requirement',
      (tester) async {
    final orgRepo = _FakeOrganisationOpeningsRepository(
      [_assignedRequirement()],
      'available',
    );
    await _pump(tester, orgRepo: orgRepo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Close Requirement'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Close Requirement'));
    await tester.pumpAndSettle();

    expect(find.textContaining("now available for new jobs"), findsOneWidget);
  });

  testWidgets('shows a highlighted red date range next to the salary for an assigned date_range requirement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository()),
          organisationOpeningsRepositoryProvider.overrideWithValue(
            _FakeOrganisationOpeningsRepository([
              _assignedRequirement(scheduleType: 'date_range', startDate: '2026-08-25', endDate: '2026-09-05'),
            ]),
          ),
        ],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    // Not pumpAndSettle: the schedule badge blinks via a repeating
    // AnimationController by design, so it never "settles".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('₹40000/month'), findsOneWidget);
    expect(find.text('2026-08-25 – 2026-09-05'), findsOneWidget);
    final salaryStyle = tester.widget<Text>(find.text('₹40000/month')).style!;
    final scheduleStyle = tester.widget<Text>(find.text('2026-08-25 – 2026-09-05')).style!;
    expect(scheduleStyle.color, AppColors.error);
    expect(scheduleStyle.fontSize, salaryStyle.fontSize);
  });

  testWidgets('shows a highlighted red day list for an assigned specific_days/monthly requirement', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository()),
          organisationOpeningsRepositoryProvider.overrideWithValue(
            _FakeOrganisationOpeningsRepository([
              _assignedRequirement(scheduleType: 'specific_days', scheduleRepeat: 'monthly', specificDays: [5, 15, 25]),
            ]),
          ),
        ],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Days: 5, 15, 25'), findsOneWidget);
    final scheduleStyle = tester.widget<Text>(find.text('Days: 5, 15, 25')).style!;
    expect(scheduleStyle.color, AppColors.error);
  });

  testWidgets('shows a highlighted red weekday list for an assigned specific_days/weekly requirement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsRepositoryProvider.overrideWithValue(_FakeJobsRepository()),
          organisationOpeningsRepositoryProvider.overrideWithValue(
            _FakeOrganisationOpeningsRepository([
              _assignedRequirement(scheduleType: 'specific_days', scheduleRepeat: 'weekly', specificDays: [2, 4]),
            ]),
          ),
        ],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Every: Tue, Thu'), findsOneWidget);
    final scheduleStyle = tester.widget<Text>(find.text('Every: Tue, Thu')).style!;
    expect(scheduleStyle.color, AppColors.error);
  });
}
