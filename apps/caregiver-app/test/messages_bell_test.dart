import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:caregiver_app/app/messages_bell.dart';
import 'package:caregiver_app/core/caregiver_messages/caregiver_messages_repository.dart';
import 'package:caregiver_app/core/network/api_exception.dart';
import 'package:caregiver_app/core/providers.dart';
import 'package:caregiver_app/core/storage/local_storage.dart';
import 'package:caregiver_app/features/jobs/data/jobs_repository.dart';

/// Equivalent to pumpAndSettle(), but safe once the bell's swing animation
/// is running — it repeats forever via AnimationController while there's
/// at least one unread message, so a real pumpAndSettle() never observes an
/// idle frame and times out (same reasoning as nursenow-app's own
/// messages_bell_test.dart's _settle() helper).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

JobModel _job({String id = 'job-1', int adminJobNumber = 512, Map<String, dynamic>? myApplication}) {
  return JobModel.fromJson({
    'id': id,
    'admin_job_number': adminJobNumber,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': '1800',
    'status': 'active',
    'posted_by': 'admin-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    if (myApplication != null) 'my_application': myApplication,
  });
}

Map<String, dynamic> _appliedApplication() => {
      'status': 'applied',
      'applied_at': '2026-08-01T10:00:00Z',
      'accepted_at': null,
      'rejected_at': null,
      'completed_at': null,
      'reapplied_at': null,
      'decided_by_admin': false,
      'decline_reason': null,
    };

class _FakeJobsRepository extends JobsRepository {
  final List<JobModel> activeJobs;
  final List<JobModel> assignedJobs;
  final ApiException? error;

  _FakeJobsRepository({this.activeJobs = const [], this.assignedJobs = const [], this.error}) : super(Dio());

  @override
  Future<List<JobModel>> listActiveJobs() async {
    if (error != null) throw error!;
    return activeJobs;
  }

  @override
  Future<List<JobModel>> getAssignedJobs() async {
    if (error != null) throw error!;
    return assignedJobs;
  }
}

CaregiverMessageModel _template({required String id, required String event, required String message}) =>
    CaregiverMessageModel(id: id, event: event, icon: MessageIcon.info, message: message, displayOrder: 10, enabled: true);

List<CaregiverMessageModel> _seedTemplates() => [
      _template(id: 'm1', event: CaregiverMessageEvent.jobApplied, message: 'Successfully applied to job {job_id}'),
      _template(id: 'm2', event: CaregiverMessageEvent.welcome, message: 'Welcome to NurseJobs!'),
    ];

class _FakeCaregiverMessagesRepository extends CaregiverMessagesRepository {
  final List<CaregiverMessageModel> templates;

  _FakeCaregiverMessagesRepository({this.templates = const []}) : super(Dio());

  @override
  Future<List<CaregiverMessageModel>> get() async => templates;
}

Future<LocalStorage> _pump(
  WidgetTester tester,
  _FakeJobsRepository repo, {
  List<CaregiverMessageModel>? templates,
  Map<String, Object>? initialPrefs,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(initialPrefs ?? {});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        jobsRepositoryProvider.overrideWithValue(repo),
        caregiverMessagesRepositoryProvider.overrideWithValue(
          _FakeCaregiverMessagesRepository(templates: templates ?? _seedTemplates()),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [MessagesBellButton()])),
      ),
    ),
  );
  await _settle(tester);
  return localStorage;
}

void main() {
  testWidgets('shows an unread badge matching the number of currently-applicable messages', (tester) async {
    await _pump(tester, _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]));

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('shows no badge once every applicable message has already been read on this device', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]),
      initialPrefs: {
        'read_message_ids': ['m1'],
      },
    );

    expect(find.text('1'), findsNothing);
  });

  testWidgets('tapping the bell opens an overlay with the applicable messages, not a new page', (tester) async {
    await _pump(tester, _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    expect(find.textContaining('Successfully applied to job ADMIN-JOB-512'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('opening the overlay alone does not mark anything read or change the badge', (tester) async {
    final localStorage = await _pump(tester, _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]));

    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    expect(find.text('1'), findsOneWidget);
    expect(localStorage.readMessageIds, isEmpty);
  });

  testWidgets('tapping a message row opens it in a popup, not marked read yet', (tester) async {
    final localStorage = await _pump(tester, _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    await tester.tap(find.textContaining('Successfully applied to job ADMIN-JOB-512').first);
    await _settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(localStorage.readMessageIds, isEmpty);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('closing the popup via Close marks that message read and decrements the badge', (tester) async {
    final localStorage = await _pump(tester, _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);
    await tester.tap(find.textContaining('Successfully applied to job ADMIN-JOB-512').first);
    await _settle(tester);

    await tester.tap(find.text('Close'));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(localStorage.readMessageIds, {'m1'});
    expect(find.text('1'), findsNothing);
  });

  testWidgets('dismissing the popup via the barrier also marks it read', (tester) async {
    final localStorage = await _pump(tester, _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);
    await tester.tap(find.textContaining('Successfully applied to job ADMIN-JOB-512').first);
    await _settle(tester);

    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(localStorage.readMessageIds, {'m1'});
  });

  testWidgets('a previously-read message contributes nothing to a later unread count', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository(activeJobs: [_job(myApplication: _appliedApplication())]),
      initialPrefs: {
        'read_message_ids': ['m1'],
      },
    );

    expect(find.text('1'), findsNothing);
  });

  testWidgets('fails open (no crash, no badge) when the jobs fetch errors', (tester) async {
    await _pump(
      tester,
      _FakeJobsRepository(error: const ApiException(message: 'Network error', code: 'GEN_003')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('shows the welcome message when the caregiver has never applied to any job', (tester) async {
    await _pump(tester, _FakeJobsRepository());

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    expect(find.textContaining('Welcome to NurseJobs'), findsOneWidget);
  });
}
