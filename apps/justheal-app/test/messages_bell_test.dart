import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/patient_hospital/app/messages_bell.dart';
import 'package:nursenow_app/patient_hospital/core/individual_messages/individual_messages_repository.dart';
import 'package:nursenow_app/patient_hospital/core/network/api_exception.dart';
import 'package:nursenow_app/patient_hospital/core/providers.dart';
import 'package:nursenow_app/patient_hospital/core/storage/local_storage.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/patient_hospital/features/auth/state/session_state.dart';
import 'package:nursenow_app/patient_hospital/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/data/organisation_repository.dart';

/// Equivalent to pumpAndSettle(), but safe once the bell's swing animation
/// is running — it repeats forever via AnimationController while there's
/// at least one unread message, so a real pumpAndSettle() never observes an
/// idle frame and times out (same reasoning as jobs_posted_screen_test.dart's
/// own _settle() helper, written for the identical reason around
/// _StatusBadge's blink animation).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

JobModel _requirement({String status = 'active'}) {
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
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  final List<JobModel> requirements;
  final ApiException? error;

  _FakeIndividualRepository({this.requirements = const [], this.error}) : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async {
    if (error != null) throw error!;
    return requirements;
  }

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => const [];
}

IndividualMessageModel _template({required String id, required String event, required String message}) =>
    IndividualMessageModel(id: id, event: event, icon: MessageIcon.info, message: message, displayOrder: 10, enabled: true);

List<IndividualMessageModel> _seedTemplates() => [
      _template(id: 'm1', event: MessageEvent.requirementLive, message: 'You can edit this job and change salary.'),
      _template(id: 'm2', event: MessageEvent.welcome, message: 'Welcome to NurseNow!'),
    ];

class _FakeIndividualMessagesRepository extends IndividualMessagesRepository {
  final List<IndividualMessageModel> templates;

  _FakeIndividualMessagesRepository({this.templates = const []}) : super(Dio());

  @override
  Future<List<IndividualMessageModel>> get() async => templates;
}

Future<LocalStorage> _pump(
  WidgetTester tester,
  _FakeIndividualRepository repo, {
  List<IndividualMessageModel>? templates,
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
          _FakeIndividualMessagesRepository(templates: templates ?? _seedTemplates()),
        ),
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
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('shows no badge once every applicable message has already been read on this device', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'read_message_ids': ['m1'],
    });
    final localStorage = await LocalStorage.create();
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          individualRepositoryProvider.overrideWithValue(repo),
          individualMessagesRepositoryProvider.overrideWithValue(
            _FakeIndividualMessagesRepository(templates: _seedTemplates()),
          ),
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
        child: MaterialApp(home: Scaffold(appBar: AppBar(actions: const [MessagesBellButton()]))),
      ),
    );
    await _settle(tester);

    expect(find.text('1'), findsNothing);
  });

  testWidgets('tapping the bell opens an overlay with the applicable messages, not a new page', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    expect(find.textContaining('You can edit this job and change salary'), findsOneWidget);
    expect(find.text('Click on the below message to mark it read.'), findsOneWidget);
    // Still the same route — no page navigation happened, just a sheet.
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('opening the overlay alone does not mark anything read or change the badge', (tester) async {
    final localStorage = await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    // Still 1 unread — merely opening the sheet must not itself mark
    // anything read. The badge is drawn on the AppBar, still mounted
    // underneath the sheet, so it stays visible/queryable while open.
    expect(find.text('1'), findsOneWidget);
    expect(localStorage.readMessageIds, isEmpty);
  });

  testWidgets('tapping a message row opens it in a popup, not marked read yet', (tester) async {
    final localStorage = await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);

    await tester.tap(find.textContaining('You can edit this job and change salary').first);
    await _settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(localStorage.readMessageIds, isEmpty);
    // Badge is unchanged while the popup is merely open.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('closing the popup via Close marks that message read and decrements the badge', (tester) async {
    final localStorage = await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);
    await tester.tap(find.textContaining('You can edit this job and change salary').first);
    await _settle(tester);

    await tester.tap(find.text('Close'));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(localStorage.readMessageIds, {'m1'});
    expect(find.text('1'), findsNothing);
  });

  testWidgets('dismissing the popup via the barrier also marks it read', (tester) async {
    final localStorage = await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);
    await tester.tap(find.textContaining('You can edit this job and change salary').first);
    await _settle(tester);

    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(localStorage.readMessageIds, {'m1'});
  });

  testWidgets('reading one of two messages leaves the other unread', (tester) async {
    final templates = [
      _template(id: 'm1', event: MessageEvent.requirementLive, message: 'You can edit this job and change salary.'),
      _template(id: 'm3', event: MessageEvent.requirementLive, message: 'You can post one requirement at a time.'),
    ];
    final localStorage = await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'active')]),
      templates: templates,
    );

    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Messages'));
    await _settle(tester);
    await tester.tap(find.textContaining('You can edit this job and change salary').first);
    await _settle(tester);
    await tester.tap(find.text('Close'));
    await _settle(tester);

    expect(localStorage.readMessageIds, {'m1'});
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.textContaining('You can post one requirement at a time').first);
    await _settle(tester);
    await tester.tap(find.text('Close'));
    await _settle(tester);

    expect(localStorage.readMessageIds, {'m1', 'm3'});
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('a previously-read message contributes nothing to a later unread count', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final localStorage = await LocalStorage.create();
    await localStorage.markMessagesRead(['m1']);
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(localStorage),
          individualRepositoryProvider.overrideWithValue(repo),
          individualMessagesRepositoryProvider.overrideWithValue(
            _FakeIndividualMessagesRepository(templates: _seedTemplates()),
          ),
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
        child: MaterialApp(home: Scaffold(appBar: AppBar(actions: const [MessagesBellButton()]))),
      ),
    );
    await _settle(tester);

    expect(find.text('1'), findsNothing);
  });

  testWidgets('fails open (no crash, no badge) when the requirements fetch errors', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(error: ApiException(message: 'Network error', code: 'GEN_003')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsNothing);
  });
}
