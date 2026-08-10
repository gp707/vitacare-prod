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

JobModel _job({String status = 'active'}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'work_type': 'bedside_care',
    'city': 'bangalore',
    'description': 'Need a bedside caregiver',
    'duty_timings': '24hrs_live_in',
    'language': 'hindi',
    'gender_needed': 'female',
    'religion': 'hindu',
    'status': status,
    'posted_by': 'admin-1',
    'created_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeAdminJobsRepository extends AdminJobsRepository {
  List<JobModel> jobs;
  bool createCalled = false;
  bool closeCalled = false;
  String? remindedJobId;

  _FakeAdminJobsRepository(this.jobs) : super(Dio());

  @override
  Future<List<JobModel>> list({String? status}) async => jobs;

  @override
  Future<(JobModel, List<JobResponseModel>)> getDetail(String jobId) async {
    return (jobs.first, <JobResponseModel>[]);
  }

  @override
  Future<void> create({
    required String workType,
    required String city,
    required String description,
    required String dutyTimings,
    required String language,
    required String genderNeeded,
    required String religion,
  }) async {
    createCalled = true;
    jobs = [...jobs, _job()];
  }

  @override
  Future<void> close(String jobId) async {
    closeCalled = true;
    jobs = jobs.map((j) => _job(status: 'closed')).toList();
  }

  @override
  Future<void> remind(String jobId) async {
    remindedJobId = jobId;
  }
}

Future<void> _pump(WidgetTester tester, _FakeAdminJobsRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage)
            ..state = AdminSessionAuthenticated(userId: 'u1', role: 'super_admin'),
        ),
        adminJobsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: AdminJobsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists posted jobs with work type and status', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    expect(find.text('Bedside Care (includes diaper change)'), findsOneWidget);
    expect(find.text('active'), findsOneWidget);
  });

  testWidgets('shows Close for an active job but not a closed one', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(status: 'active'), _job(status: 'closed')]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
  });

  testWidgets('Post New Job opens a dialog; submitting calls create()', (tester) async {
    final repo = _FakeAdminJobsRepository([]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post New Job'));
    await tester.pumpAndSettle();

    expect(find.text('Post New Job'), findsWidgets); // button label + dialog title

    for (final label in ['Work Type', 'City', 'Duty Timings', 'Language', 'Gender Needed', 'Religion']) {
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_firstMenuOptionLabel(label)).last);
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Need a caregiver urgently');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Post'));
    await tester.pumpAndSettle();

    expect(repo.createCalled, isTrue);
  });

  testWidgets('tapping Close calls the repository and refreshes', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(repo.closeCalled, isTrue);
  });

  testWidgets('shows Remind for an active job but not a closed one', (tester) async {
    final repo = _FakeAdminJobsRepository([_job(status: 'active'), _job(status: 'closed')]);
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Remind'), findsOneWidget);
  });

  testWidgets('tapping Remind calls the repository with the job id', (tester) async {
    final repo = _FakeAdminJobsRepository([_job()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Remind'));
    await tester.pumpAndSettle();

    expect(repo.remindedJobId, 'job-1');
  });
}

String _firstMenuOptionLabel(String fieldLabel) {
  switch (fieldLabel) {
    case 'Work Type':
      return 'Companion Care';
    case 'City':
      return 'Bangalore';
    case 'Duty Timings':
      return '24Hrs (Live-In)';
    case 'Language':
      return 'Hindi';
    case 'Gender Needed':
      return 'Male';
    case 'Religion':
      return 'Hindu';
    default:
      throw ArgumentError(fieldLabel);
  }
}
