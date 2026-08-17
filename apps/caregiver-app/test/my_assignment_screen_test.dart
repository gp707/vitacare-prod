import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/my_assignment_screen.dart';

JobModel _assignedJob({
  String id = 'job-1',
  int jobNumber = 42,
  String applicationStatus = 'accepted',
}) {
  return JobModel.fromJson({
    'id': id,
    'job_number': jobNumber,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver for an elderly patient',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'languages': ['hindi'],
    'salary_monthly': 30000,
    'preferred_gender': 'female',
    'status': 'closed',
    'posted_by': 'admin-1',
    'posted_at': DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'my_application': {
      'status': applicationStatus,
      'applied_at': '2026-08-01T10:00:00Z',
      'accepted_at': '2026-08-02T10:00:00Z',
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

class _FakeJobsRepository extends JobsRepository {
  List<JobModel> jobs;
  String? completedJobId;
  bool completeStillAssigned;
  _FakeJobsRepository(this.jobs, {this.completeStillAssigned = false}) : super(Dio());

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

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('shows the assigned job details, including care receiver', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('78 yrs'), findsOneWidget);
    expect(find.text('Admin Kumar'), findsOneWidget);
    expect(find.text('+919876500000'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Call'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Mark Complete'), findsOneWidget);
  });

  testWidgets("shows an empty state when there are no accepted jobs", (tester) async {
    final fakeRepo = _FakeJobsRepository([]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You don't have any accepted jobs yet."), findsOneWidget);
  });

  testWidgets('lists every accepted/completed job — a caregiver can hold more than one at once', (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _assignedJob(id: 'job-1', jobNumber: 42, applicationStatus: 'accepted'),
      _assignedJob(id: 'job-2', jobNumber: 43, applicationStatus: 'completed'),
    ]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('Job #43'), findsOneWidget);
    // Only the accepted job gets the action button; the completed one shows a badge instead.
    expect(find.widgetWithText(OutlinedButton, 'Mark Complete'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('You were accepted for this job'), findsOneWidget);
  });

  testWidgets('tapping Mark Complete, confirming, calls completeJob and refreshes the list', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark Complete'));
    await tester.pumpAndSettle();

    // Confirmation dialog appears first — tapping outside/Cancel wouldn't call the API.
    expect(find.text('Mark job as complete?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Complete'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedJobId, 'job-1');
    expect(find.text('Completed'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Mark Complete'), findsNothing);
  });

  testWidgets('cancelling the confirmation dialog does not call completeJob', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark Complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fakeRepo.completedJobId, isNull);
    expect(find.widgetWithText(OutlinedButton, 'Mark Complete'), findsOneWidget);
  });

  testWidgets('shows a snackbar mentioning availability when completing the last accepted job', (tester) async {
    final fakeRepo = _FakeJobsRepository([_assignedJob()], completeStillAssigned: false);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: MyAssignmentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark Complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Complete'));
    await tester.pumpAndSettle();

    expect(find.textContaining("now available for new jobs"), findsOneWidget);
  });
}
