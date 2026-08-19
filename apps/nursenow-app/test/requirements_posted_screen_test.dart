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
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';
import 'package:nursenow_app/features/organisation/screens/requirements_posted_screen.dart';

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  int requirementNumber = 5,
  String status = 'active',
  int? salaryAmount = 40000,
  String? frequencyOfCare = 'monthly',
  String? rejectionReason,
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': 'registered_nurse',
    'frequency_of_care': frequencyOfCare,
    'salary_amount': salaryAmount,
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Wound care',
    'status': status,
    'rejection_reason': rejectionReason,
    'posted_at': '2026-08-01T10:00:00Z',
  });
}

OrganisationRequirementApplicationModel _application({
  String id = 'app-1',
  String requirementId = 'req-1',
  String status = 'applied',
}) {
  return OrganisationRequirementApplicationModel.fromJson({
    'id': id,
    'requirement_id': requirementId,
    'profile_id': 'profile-1',
    'status': status,
    'full_name': 'Test Caregiver',
    'phone': '+919876543210',
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeOrganisationRepository extends OrganisationRepository {
  List<OrganisationRequirementModel> requirements;
  Map<String, List<OrganisationRequirementApplicationModel>> applicationsByRequirementId;
  String? decidedRequirementId;
  String? decidedApplicationId;
  String? decidedStatus;

  _FakeOrganisationRepository({this.requirements = const [], this.applicationsByRequirementId = const {}})
      : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> listMyRequirements() async => requirements;

  @override
  Future<List<OrganisationRequirementApplicationModel>> listApplications(String requirementId) async =>
      applicationsByRequirementId[requirementId] ?? const [];

  @override
  Future<void> decideApplication(String requirementId, String applicationId, String status) async {
    decidedRequirementId = requirementId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
  }
}

Future<void> _pump(WidgetTester tester, _FakeOrganisationRepository repo, {bool isJobPostingBlocked = false}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        organisationRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, IndividualRepository(Dio()), repo)
            ..state = SessionAuthenticated(
              role: 'organisation',
              fullName: 'Ravi Sharma',
              phone: '+919876543210',
              isJobPostingBlocked: isJobPostingBlocked,
              organisationName: 'City Hospital',
              organisationType: 'hospital',
              city: 'bangalore',
              area: 'Indiranagar',
            ),
        ),
      ],
      child: const MaterialApp(home: RequirementsPostedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state and the Post CTA when there are no requirements yet', (tester) async {
    await _pump(tester, _FakeOrganisationRepository());

    expect(find.textContaining("don't have any requirements posted yet"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
  });

  testWidgets('the Post CTA stays visible even with multiple live requirements — no one-live limit like Individual',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [
          _requirement(id: 'req-1', requirementNumber: 1, status: 'active'),
          _requirement(id: 'req-2', requirementNumber: 2, status: 'pending_review', salaryAmount: null, frequencyOfCare: null),
        ],
      ),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNotNull);
    expect(find.text('Requirement #1'), findsOneWidget);
    expect(find.text('Requirement #2'), findsOneWidget);
  });

  testWidgets('shows requirement details: type of nurse, salary, accommodation/food, special skills',
      (tester) async {
    await _pump(tester, _FakeOrganisationRepository(requirements: [_requirement()]));

    expect(find.text('Live — visible to caregivers'), findsOneWidget);
    expect(find.text('₹40000/month'), findsOneWidget);
    expect(find.text('Registered Nurse (RN)'), findsOneWidget);
    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Wound care'), findsOneWidget);
  });

  testWidgets('shows the accepted caregiver on a closed requirement', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByRequirementId: {
          'req-1': [_application(status: 'accepted')],
        },
      ),
    );

    expect(find.text('Closed — caregiver assigned'), findsOneWidget);
    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets('accepting an applicant calls decideApplication with the right requirement and application id',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(repo.decidedRequirementId, 'req-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('disables the Post CTA and shows a message when job posting is blocked', (tester) async {
    await _pump(tester, _FakeOrganisationRepository(), isJobPostingBlocked: true);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Posting is currently blocked'), findsOneWidget);
  });
}
