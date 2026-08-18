import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/my_requirement_screen.dart';

JobModel _requirement({
  String status = 'active',
  int? salaryAmount = 1800,
  String? frequencyOfCare = 'daily',
  String? rejectionReason,
}) {
  return JobModel.fromJson({
    'id': 'job-1',
    'job_number': 42,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'languages': ['hindi'],
    'salary_amount': salaryAmount,
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'rejection_reason': rejectionReason,
  });
}

JobApplicationModel _application({String status = 'applied'}) {
  return JobApplicationModel.fromJson({
    'id': 'app-1',
    'job_id': 'job-1',
    'profile_id': 'profile-1',
    'status': status,
    'full_name': 'Test Caregiver',
    'phone': '+919876543210',
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  List<JobModel> requirements;
  List<JobApplicationModel> applications;
  String? decidedApplicationId;
  String? decidedStatus;

  _FakeIndividualRepository({this.requirements = const [], this.applications = const []}) : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async => requirements;

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => applications;

  @override
  Future<void> decideApplication(String jobId, String applicationId, String status) async {
    decidedApplicationId = applicationId;
    decidedStatus = status;
  }
}

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: MyRequirementScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state with a Post CTA when there is no requirement yet', (tester) async {
    await _pump(tester, _FakeIndividualRepository());

    expect(find.textContaining("don't have a requirement posted yet"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('shows pending_review status without salary/applicants', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(status: 'pending_review', salaryAmount: null, frequencyOfCare: null)]),
    );

    expect(find.text('Job #42'), findsOneWidget);
    expect(find.text('Pending admin review'), findsOneWidget);
    expect(find.textContaining('Applicants'), findsNothing);
  });

  testWidgets('shows the rejection reason for a closed+rejected requirement', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, rejectionReason: 'Duplicate posting')],
      ),
    );

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Reason: Duplicate posting'), findsOneWidget);
  });

  testWidgets('shows salary and applicants for an active requirement', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement()], applications: [_application()]),
    );

    expect(find.text('Live — visible to caregivers'), findsOneWidget);
    expect(find.text('₹1800/day'), findsOneWidget);
    expect(find.text('Applicants (1)'), findsOneWidget);
    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets('accepting an applicant calls decideApplication with accepted', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement()], applications: [_application()]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('shows no accept/reject buttons for an already-decided applicant', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement()], applications: [_application(status: 'accepted')]),
    );

    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reject'), findsNothing);
    expect(find.text('Accepted'), findsOneWidget);
  });
}
