import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/jobs_screen.dart';

JobModel _job({String? myApplicationStatus, String? postedAt}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver for an elderly patient',
    'duty_type': 'live_in',
    'languages': ['hindi'],
    'salary_monthly': 30000,
    'preferred_gender': 'female',
    'status': 'active',
    'posted_by': 'admin-1',
    'posted_at': postedAt ?? DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'my_application_status': myApplicationStatus,
    'care_receiver': {
      'id': 'cr-1',
      'age': 78,
      'gender': 'female',
      'weight_kg': 60,
      'mobility': 'uses_wheelchair',
      'communication': 'verbal',
      'feeding_type': 'oral_needs_assistance',
      'medical_assistance': ['medication_reminders'],
      'has_medical_condition': true,
      'medical_conditions': ['diabetes'],
      'medical_info': 'Needs help twice daily',
      'toilet_assistance': 'uses_diapers',
      'requires_vital_monitoring': true,
      'vital_monitoring_types': ['blood_pressure', 'blood_sugar'],
    },
  });
}

class _FakeJobsRepository extends JobsRepository {
  List<JobModel> jobs;
  String? appliedWith;

  _FakeJobsRepository(this.jobs) : super(Dio());

  @override
  Future<List<JobModel>> listActiveJobs() async => jobs;

  @override
  Future<String> applyToJob(String jobId, String status) async {
    appliedWith = status;
    jobs = [_job(myApplicationStatus: status)];
    return status;
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('shows job details: duty type, city, area, description', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('24Hrs - Live In in Bangalore'), findsOneWidget);
    expect(find.text('Indiranagar'), findsOneWidget);
    expect(find.text('Need a caregiver for an elderly patient'), findsOneWidget);
  });

  testWidgets(
      'groups patient identity, patient condition, and caregiver requirement details into clearly labeled sections',
      (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // About Patient
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('78 yrs'), findsOneWidget);
    expect(find.text('Female'), findsWidgets); // patient gender tag + preferred-gender tag
    expect(find.text('60 kg'), findsOneWidget);
    expect(find.text('Uses wheelchair'), findsOneWidget);
    expect(find.text('Can Speak/Communicate'), findsOneWidget);
    expect(find.text('Oral feeding – needs assistance'), findsOneWidget);

    // About Patient Condition
    expect(find.text('About Patient Condition'), findsOneWidget);
    expect(find.text('Medication reminders'), findsOneWidget);
    expect(find.text('Toilet: Uses diapers'), findsOneWidget);
    expect(find.text('Diabetes'), findsOneWidget);
    expect(find.text('Monitor: Blood pressure'), findsOneWidget);
    expect(find.text('Monitor: Blood sugar'), findsOneWidget);
    expect(find.text('Needs help twice daily'), findsOneWidget);

    // About Nurse/Caregiver Requirement
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Hindi'), findsOneWidget);
  });

  testWidgets('shows the job number and salary highlighted at the top', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('₹30000/month'), findsOneWidget);
  });

  testWidgets('shows days-left urgency for a freshly-posted job', (tester) async {
    final freshRepo = _FakeJobsRepository([
      _job(postedAt: DateTime.now().toUtc().toIso8601String()),
    ]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(freshRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('left to apply'), findsOneWidget);
  });

  testWidgets('shows "window closed" once the 3-day apply-by window has passed (informational only)',
      (tester) async {
    final expiredRepo = _FakeJobsRepository([
      _job(postedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)).toIso8601String()),
    ]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(expiredRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Application window closed'), findsOneWidget);
    // Informational only — Apply/Reject stay active even past the window.
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsOneWidget);
  });

  testWidgets('shows Apply/Reject when the caregiver has not applied yet', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'More Info'), findsNothing);
  });

  testWidgets('shows the application status instead of buttons once already applied', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job(myApplicationStatus: 'applied')]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You applied'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsNothing);
  });

  testWidgets('shows a declined label when rejected', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job(myApplicationStatus: 'rejected')]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You declined'), findsOneWidget);
  });

  testWidgets('tapping Apply calls applyToJob with applied', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'applied');
  });

  testWidgets('tapping Reject calls applyToJob with rejected', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(fakeRepo.appliedWith, 'rejected');
  });

  testWidgets('shows an empty state when there are no active jobs', (tester) async {
    final fakeRepo = _FakeJobsRepository([]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No jobs posted right now'), findsOneWidget);
  });
}
