import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/individual_messages/individual_messages_repository.dart';
import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/scope_of_work/scope_of_work_repository.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/messages_screen.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

JobModel _requirement({
  String status = 'active',
  Map<String, dynamic>? careReceiver,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'patient_job_number': 542,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': 'daily',
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': '1800',
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    if (careReceiver != null) 'care_receiver': careReceiver,
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  final List<JobModel> requirements;
  final ApiException? error;
  final List<JobApplicationModel> applications;
  final ApiException? applicationsError;
  int listApplicationsCallCount = 0;

  _FakeIndividualRepository({
    this.requirements = const [],
    this.error,
    this.applications = const [],
    this.applicationsError,
  }) : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async {
    if (error != null) throw error!;
    return requirements;
  }

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async {
    listApplicationsCallCount++;
    if (applicationsError != null) throw applicationsError!;
    return applications;
  }
}

class _FakeScopeOfWorkRepository extends ScopeOfWorkRepository {
  _FakeScopeOfWorkRepository() : super(Dio());

  @override
  Future<ScopeOfWorkModel> get() async => const ScopeOfWorkModel(
        companionCare: ['Companion bullet'],
        bedsideCare: ['Bedside bullet'],
        criticalCare: ['Critical bullet'],
      );
}

IndividualMessageModel _template({
  required String id,
  required String event,
  required String message,
  required int displayOrder,
}) =>
    IndividualMessageModel(
      id: id,
      event: event,
      icon: MessageIcon.info,
      message: message,
      displayOrder: displayOrder,
      enabled: true,
    );

/// Mirrors the real migration seed content closely enough for the existing
/// text assertions below to keep working unchanged.
List<IndividualMessageModel> _seedTemplates() => [
      _template(
        id: 'm1',
        event: MessageEvent.requirementLive,
        message: 'You can edit this job and change salary.',
        displayOrder: 10,
      ),
      _template(
        id: 'm3',
        event: MessageEvent.requirementLive,
        message: 'You can post one requirement at a time.',
        displayOrder: 30,
      ),
      _template(
        id: 'm4',
        event: MessageEvent.requirementLive,
        message: 'If you are not getting applicants, consider widening your scope.',
        displayOrder: 40,
      ),
      _template(
        id: 'm5',
        event: MessageEvent.welcome,
        message: 'Welcome to NurseNow!',
        displayOrder: 10,
      ),
      _template(
        id: 'm6',
        event: MessageEvent.welcome,
        message: 'Ready to get started? Post a Requirement.',
        displayOrder: 20,
      ),
    ];

class _FakeIndividualMessagesRepository extends IndividualMessagesRepository {
  final List<IndividualMessageModel> templates;
  final ApiException? error;

  _FakeIndividualMessagesRepository({this.templates = const [], this.error}) : super(Dio());

  @override
  Future<List<IndividualMessageModel>> get() async {
    if (error != null) throw error!;
    return templates;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeIndividualRepository repo, {
  List<IndividualMessageModel>? templates,
  ApiException? messagesError,
}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        individualMessagesRepositoryProvider.overrideWithValue(
          _FakeIndividualMessagesRepository(templates: templates ?? _seedTemplates(), error: messagesError),
        ),
        scopeOfWorkRepositoryProvider.overrideWithValue(_FakeScopeOfWorkRepository()),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
            ..state = const SessionAuthenticated(
              role: 'individual',
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: false,
            ),
        ),
      ],
      child: const MaterialApp(home: MessagesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the welcome/orientation messages for an account with no requirements at all', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: []));

    expect(find.textContaining('Welcome to NurseNow'), findsOneWidget);
    expect(find.textContaining('Post a Requirement'), findsOneWidget);
    expect(find.text('No messages right now.'), findsNothing);
  });

  testWidgets('shows a friendly empty state once the account has posted before but nothing is live now',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'closed')]),
    );

    expect(find.text('No messages right now.'), findsOneWidget);
    expect(find.textContaining('Welcome to NurseNow'), findsNothing);
  });

  testWidgets('shows the automatic messages for a live requirement', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'active')]),
    );

    expect(find.textContaining('You can edit this job and change salary'), findsOneWidget);
    expect(find.textContaining('You can post one requirement at a time'), findsOneWidget);
    expect(find.textContaining('consider widening your scope'), findsOneWidget);
  });

  testWidgets('shows a friendly error instead of crashing when the fetch fails', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(error: ApiException(message: 'Network error', code: 'GEN_003')),
    );

    expect(find.text('Network error'), findsOneWidget);
  });

  testWidgets('shows a friendly error instead of crashing when the message-templates fetch fails',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'active')]),
      messagesError: ApiException(message: 'Could not load messages', code: 'GEN_003'),
    );

    expect(find.text('Could not load messages'), findsOneWidget);
  });

  testWidgets('does not fetch applications when there is no requirement yet', (tester) async {
    final repo = _FakeIndividualRepository(requirements: []);
    await _pump(tester, repo);

    expect(repo.listApplicationsCallCount, 0);
  });

  testWidgets('does not fetch applications when the most recent requirement is still pending_review',
      (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review')]);
    await _pump(tester, repo);

    expect(repo.listApplicationsCallCount, 0);
  });

  testWidgets('fetches applications and shows the accepted tip even though acceptance closed the requirement',
      (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed')],
      applications: [
        JobApplicationModel(
          id: 'app-1',
          jobId: 'job-1',
          profileId: 'profile-1',
          status: 'accepted',
          fullName: 'Test Caregiver',
          phone: '+919876543210',
          updatedAt: '2026-08-01T10:00:00Z',
        ),
      ],
    );
    final templates = [
      _template(
        id: 'accepted',
        event: MessageEvent.caregiverAccepted,
        message: 'A caregiver accepted your requirement!',
        displayOrder: 10,
      ),
    ];

    await _pump(tester, repo, templates: templates);

    expect(repo.listApplicationsCallCount, 1);
    expect(find.textContaining('A caregiver accepted your requirement'), findsOneWidget);
  });

  testWidgets('shows a friendly error instead of crashing when the applications fetch fails', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'active')],
      applicationsError: ApiException(message: 'Could not load applications', code: 'GEN_003'),
    );
    await _pump(tester, repo);

    expect(find.text('Could not load applications'), findsOneWidget);
  });
}
