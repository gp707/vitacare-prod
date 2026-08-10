import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/jobs_screen.dart';

JobModel _job({String? myResponse}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'work_type': 'bedside_care',
    'city': 'bangalore',
    'description': 'Need a bedside caregiver for an elderly patient',
    'duty_timings': '24hrs_live_in',
    'language': 'hindi',
    'gender_needed': 'female',
    'religion': 'hindu',
    'status': 'active',
    'posted_by': 'admin-1',
    'created_at': '2026-08-01T10:00:00Z',
    'my_response': myResponse,
  });
}

class _FakeJobsRepository extends JobsRepository {
  List<JobModel> jobs;
  String? respondedWith;
  String? respondedMessage;

  _FakeJobsRepository(this.jobs) : super(Dio());

  @override
  Future<List<JobModel>> listActiveJobs() async => jobs;

  @override
  Future<String> respondToJob(String jobId, String response, {String? message}) async {
    respondedWith = response;
    respondedMessage = message;
    jobs = [_job(myResponse: response)];
    return response;
  }
}

Future<void> _pumpTall(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(400, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  testWidgets('shows job details: work type, salary range, tags, description', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bedside Care (includes diaper change)'), findsOneWidget);
    expect(find.text('₹28000 – ₹35000'), findsOneWidget);
    expect(find.text('Bangalore'), findsOneWidget);
    expect(find.text('Need a bedside caregiver for an elderly patient'), findsOneWidget);
  });

  testWidgets('shows Accept/Reject/More Info when the caregiver has not responded yet', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'More Info'), findsOneWidget);
  });

  testWidgets('shows the response status instead of buttons once already responded', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job(myResponse: 'accepted')]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You responded: Accepted'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Accept'), findsNothing);
  });

  testWidgets('tapping Accept calls respondToJob with accepted, no message', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(fakeRepo.respondedWith, 'accepted');
    expect(fakeRepo.respondedMessage, isNull);
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

  testWidgets('asking for more details prompts for a message and sends it', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job()]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'More Info'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What are the exact hours?');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(fakeRepo.respondedWith, 'more_details');
    expect(fakeRepo.respondedMessage, 'What are the exact hours?');
  });
}
