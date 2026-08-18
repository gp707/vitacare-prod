import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/jobs_posted_screen.dart';

JobModel _requirement({
  String id = 'job-1',
  int jobNumber = 42,
  String status = 'active',
  int? salaryAmount = 1800,
  String? frequencyOfCare = 'daily',
  String? rejectionReason,
  Map<String, dynamic>? careReceiver,
}) {
  return JobModel.fromJson({
    'id': id,
    'job_number': jobNumber,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Needs help with daily routine.',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': '2026-09-01',
    'languages': ['hindi'],
    'salary_amount': salaryAmount,
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'rejection_reason': rejectionReason,
    if (careReceiver != null) 'care_receiver': careReceiver,
  });
}

final _careReceiverJson = {
  'id': 'cr-1',
  'age': 74,
  'gender': 'female',
  'weight_kg': 58,
  'mobility': 'walks_independently',
  'communication': 'verbal',
  'feeding_type': 'oral_independent',
  'medical_assistance': ['medication_reminders'],
  'has_medical_condition': false,
  'medical_conditions': [],
  'toilet_assistance': ['independent'],
  'requires_vital_monitoring': false,
  'vital_monitoring_types': [],
};

JobApplicationModel _application({String id = 'app-1', String jobId = 'job-1', String status = 'applied'}) {
  return JobApplicationModel.fromJson({
    'id': id,
    'job_id': jobId,
    'profile_id': 'profile-1',
    'status': status,
    'full_name': 'Test Caregiver',
    'phone': '+919876543210',
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  List<JobModel> requirements;
  Map<String, List<JobApplicationModel>> applicationsByJobId;
  String? decidedJobId;
  String? decidedApplicationId;
  String? decidedStatus;

  _FakeIndividualRepository({this.requirements = const [], this.applicationsByJobId = const {}}) : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async => requirements;

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => applicationsByJobId[jobId] ?? const [];

  @override
  Future<void> decideApplication(String jobId, String applicationId, String status) async {
    decidedJobId = jobId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
  }
}

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo, {bool isJobPostingBlocked = false}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo)
            ..state = SessionAuthenticated(
              fullName: 'Asha Patel',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
            ),
        ),
      ],
      child: const MaterialApp(home: JobsPostedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state with a Post CTA when there are no requirements yet', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    expect(find.textContaining("don't have any requirements posted yet"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('shows the Post CTA again once the only requirement is closed (not live)', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)]),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('shows the Post CTA again once the only requirement was rejected', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, rejectionReason: 'Duplicate posting')],
      ),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('hides the Post CTA while a pending_review requirement is live', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review', salaryAmount: null, frequencyOfCare: null)]),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsNothing);
  });

  testWidgets('hides the Post CTA while an active requirement is live', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement(status: 'active')]));

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsNothing);
  });

  testWidgets('shows the full requirement history, most recent first, not just the current one', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-2', jobNumber: 43, status: 'active'),
          _requirement(id: 'job-1', jobNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
        ],
      ),
    );

    expect(find.text('Job #43'), findsOneWidget);
    expect(find.text('Job #42'), findsOneWidget);
  });

  testWidgets('shows the accepted caregiver on a closed requirement, not just while active', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    expect(find.text('Closed — caregiver assigned'), findsOneWidget);
    expect(find.text('Applicants (1)'), findsOneWidget);
    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets('renders the full About Patient / requirement detail inline', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('74 yrs'), findsOneWidget);
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.text('Needs help with daily routine.'), findsOneWidget);
  });

  testWidgets('accepting an applicant calls decideApplication with the right job and application id', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('disables the Post CTA and shows a message when job posting is blocked', (tester) async {
    await _pump(tester, _FakeIndividualRepository(), isJobPostingBlocked: true);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Posting is currently blocked'), findsOneWidget);
  });
}
