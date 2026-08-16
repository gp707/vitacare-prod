import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/jobs_screen.dart';

JobModel _job({String? myApplicationStatus}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Need a caregiver for an elderly patient',
    'duty_type': 'live_in',
    'languages': ['hindi'],
    'preferred_gender': 'female',
    'status': 'active',
    'posted_by': 'admin-1',
    'created_at': '2026-08-01T10:00:00Z',
    'my_application_status': myApplicationStatus,
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
