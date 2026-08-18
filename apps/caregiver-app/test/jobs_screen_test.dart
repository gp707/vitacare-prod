import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';
import 'package:caregiver_app/features/jobs/screens/jobs_screen.dart';
import 'package:caregiver_app/features/jobs/widgets/job_detail_card.dart';

// Same conversion the app applies (UTC -> local) so assertions don't
// depend on the test machine's timezone.
String _expected(String isoUtc) => formatDateTime(DateTime.parse(isoUtc).toLocal());

JobModel _job({
  Map<String, dynamic>? myApplication,
  String? postedAt,
  Object? description = 'Need a caregiver for an elderly patient',
  String frequencyOfCare = 'daily',
  String? startDate,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': description,
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': startDate,
    'languages': ['hindi'],
    'salary_amount': 30000,
    'preferred_gender': 'female',
    'status': 'active',
    'posted_by': 'admin-1',
    'posted_at': postedAt ?? DateTime.now().toUtc().toIso8601String(),
    'created_at': '2026-08-01T10:00:00Z',
    'my_application': myApplication,
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
      'medical_condition_other': 'Recovering from hip surgery',
      'toilet_assistance': ['uses_diapers', 'uses_catheter'],
      'toilet_assistance_other': 'Needs a raised commode seat',
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
    jobs = [
      _job(myApplication: {
        'status': status,
        'applied_at': status == 'applied' ? '2026-08-17T10:00:00Z' : null,
        'accepted_at': null,
        'rejected_at': status == 'rejected' ? '2026-08-17T10:00:00Z' : null,
        'decided_by_admin': false,
      }),
    ];
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

  testWidgets('renders fine and shows no description line when the job has none set (now optional)',
      (tester) async {
    final fakeRepo = _FakeJobsRepository([_job(description: null)]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('24Hrs - Live In in Bangalore'), findsOneWidget);
    expect(find.text('Need a caregiver for an elderly patient'), findsNothing);
  });

  testWidgets(
      'groups patient identity/condition into one About Patient section, and caregiver requirement details into another',
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

    // About Patient — identity and condition are one merged section now,
    // not two separately labeled ones.
    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('About Patient Condition'), findsNothing);
    expect(find.text('78 yrs'), findsOneWidget);
    expect(find.text('Female'), findsWidgets); // patient gender tag + preferred-gender tag
    expect(find.text('60 kg'), findsOneWidget);
    expect(find.text('Uses wheelchair'), findsOneWidget);
    expect(find.text('Can Speak/Communicate'), findsOneWidget);
    expect(find.text('Oral feeding – needs assistance'), findsOneWidget);
    expect(find.text('Medicine Reminders'), findsOneWidget);
    expect(find.text('Toilet: Uses diapers'), findsOneWidget);
    expect(find.text('Toilet: Uses catheter'), findsOneWidget);
    expect(find.text('Diabetes'), findsOneWidget);
    expect(find.text('Monitor: Blood pressure'), findsOneWidget);
    expect(find.text('Monitor: Blood sugar'), findsOneWidget);
    expect(find.text('Other condition: Recovering from hip surgery'), findsOneWidget);
    expect(find.text('Other toilet assistance: Needs a raised commode seat'), findsOneWidget);

    // About Nurse/Caregiver Requirement
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.text('24Hrs - Live In'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Hindi'), findsOneWidget);
  });

  testWidgets('does not show the "other" detail lines when the care receiver has none set', (tester) async {
    final job = JobModel.fromJson({
      'id': 'job-1',
      'job_number': 42,
      'city': 'bangalore',
      'area': 'Indiranagar',
      'description': 'Need a caregiver for an elderly patient',
      'duty_type': 'live_in',
      'frequency_of_care': 'daily',
      'languages': ['hindi'],
      'salary_amount': 30000,
      'preferred_gender': 'female',
      'status': 'active',
      'posted_by': 'admin-1',
      'posted_at': DateTime.now().toUtc().toIso8601String(),
      'created_at': '2026-08-01T10:00:00Z',
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
        'toilet_assistance': ['uses_diapers'],
        'requires_vital_monitoring': false,
        'vital_monitoring_types': [],
      },
    });
    final fakeRepo = _FakeJobsRepository([job]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Other condition:'), findsNothing);
    expect(find.textContaining('Other toilet assistance:'), findsNothing);
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
    // Fixture's frequency_of_care is 'daily' — the unit follows it.
    expect(find.text('₹30000/day'), findsOneWidget);
  });

  testWidgets('shows a highlighted start date next to the salary when the job has one', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job(startDate: '2026-08-20')]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    // Not pumpAndSettle: the start date badge blinks via a repeating
    // AnimationController by design, so it never "settles".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('₹30000/day'), findsOneWidget);
    expect(find.text('Start: 2026-08-20'), findsOneWidget);
  });

  testWidgets('shows the salary unit as /month for a job with frequency_of_care monthly', (tester) async {
    final fakeRepo = _FakeJobsRepository([_job(frequencyOfCare: 'monthly')]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

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

  testWidgets('shows the applied date instead of buttons once already applied', (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _job(myApplication: {
        'status': 'applied',
        'applied_at': '2026-08-17T10:00:00Z',
        'accepted_at': null,
        'rejected_at': null,
        'decided_by_admin': false,
      }),
    ]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Applied: ${_expected('2026-08-17T10:00:00Z')}'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Apply'), findsNothing);
  });

  testWidgets('shows "Declined" (not "Declined by employer") when the caregiver declined it themselves',
      (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _job(myApplication: {
        'status': 'rejected',
        'applied_at': '2026-08-17T09:00:00Z',
        'accepted_at': null,
        'rejected_at': '2026-08-17T09:05:00Z',
        'decided_by_admin': false,
      }),
    ]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Applied: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined: ${_expected('2026-08-17T09:05:00Z')}'), findsOneWidget);
    expect(find.textContaining('Declined by employer'), findsNothing);
  });

  testWidgets(
      'shows the full real timeline — applied, accepted, then "Declined by employer" — not a bare '
      '"You declined" when an admin undoes a prior acceptance', (tester) async {
    final fakeRepo = _FakeJobsRepository([
      _job(myApplication: {
        'status': 'rejected',
        'applied_at': '2026-08-15T09:00:00Z',
        'accepted_at': '2026-08-16T09:00:00Z',
        'rejected_at': '2026-08-17T09:00:00Z',
        'decided_by_admin': true,
      }),
    ]);
    await _pumpTall(
      tester,
      ProviderScope(
        overrides: [jobsRepositoryProvider.overrideWithValue(fakeRepo)],
        child: const MaterialApp(home: JobsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Applied: ${_expected('2026-08-15T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Accepted: ${_expected('2026-08-16T09:00:00Z')}'), findsOneWidget);
    expect(find.text('Declined by employer: ${_expected('2026-08-17T09:00:00Z')}'), findsOneWidget);
    expect(find.text('You declined'), findsNothing);
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
