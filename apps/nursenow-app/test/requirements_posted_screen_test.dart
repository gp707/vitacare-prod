import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/core/network/api_exception.dart';
import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';
import 'package:nursenow_app/features/organisation/screens/requirements_posted_screen.dart';

/// Equivalent to pumpAndSettle(), but safe once a live (JobStatus.active)
/// requirement's status badge is on screen — its blink animation repeats
/// forever via AnimationController, so a real pumpAndSettle() never
/// observes an idle frame and times out (same reasoning as Individual's own
/// jobs_posted_screen_test.dart _settle helper, mirrored here since
/// _StatusBadge was duplicated onto this screen too). 500ms comfortably
/// clears every real transition in this screen (dialogs/snackbars) without
/// completing even one blink cycle (700ms).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

OrganisationRequirementModel _requirement({
  String id = 'req-1',
  int requirementNumber = 5,
  String status = 'active',
  String? rejectionReason,
  String? cancelledAt,
  String typeOfNurse = 'registered_nurse',
  String? typeOfNurseOther,
  int numberOfVacancies = 1,
  String? preferredGender,
  String durationType = 'short_term',
}) {
  return OrganisationRequirementModel.fromJson({
    'id': id,
    'requirement_number': requirementNumber,
    'posted_by': 'org-1',
    'type_of_nurse': typeOfNurse,
    'type_of_nurse_other': typeOfNurseOther,
    'accommodation_provided': true,
    'food_provided': false,
    'special_skills': 'Wound care',
    'number_of_vacancies': numberOfVacancies,
    'preferred_gender': preferredGender,
    'duration_type': durationType,
    'status': status,
    'rejection_reason': rejectionReason,
    'cancelled_at': cancelledAt,
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
  String? decidedReason;
  String? profileFetchedRequirementId;
  String? profileFetchedApplicationId;
  String? editedRequirementId;
  String? cancelledRequirementId;
  String? reactivatedRequirementId;
  ApiException? reactivateError;

  _FakeOrganisationRepository({this.requirements = const [], this.applicationsByRequirementId = const {}})
      : super(Dio());

  @override
  Future<List<OrganisationRequirementModel>> listMyRequirements() async => requirements;

  @override
  Future<List<OrganisationRequirementApplicationModel>> listApplications(String requirementId) async =>
      applicationsByRequirementId[requirementId] ?? const [];

  @override
  Future<void> decideApplication(String requirementId, String applicationId, String status, {String? reason}) async {
    decidedRequirementId = requirementId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
    decidedReason = reason;
  }

  @override
  Future<OrganisationRequirementModel> editRequirement(
    String requirementId, {
    required String typeOfNurse,
    String? typeOfNurseOther,
    required bool accommodationProvided,
    required bool foodProvided,
    String? specialSkills,
    required int numberOfVacancies,
    String? preferredGender,
    required String durationType,
  }) async {
    editedRequirementId = requirementId;
    return _requirement(id: requirementId);
  }

  @override
  Future<void> cancelRequirement(String requirementId) async {
    cancelledRequirementId = requirementId;
  }

  @override
  Future<OrganisationRequirementModel> reactivateRequirement(String requirementId) async {
    if (reactivateError != null) throw reactivateError!;
    reactivatedRequirementId = requirementId;
    return _requirement(id: requirementId, status: 'active');
  }

  @override
  Future<CaregiverProfileModel> getApplicantProfile(String requirementId, String applicationId) async {
    profileFetchedRequirementId = requirementId;
    profileFetchedApplicationId = applicationId;
    return CaregiverProfileModel.fromJson({
      'user_id': 'user-1',
      'profile_id': 'profile-1',
      'full_name': 'Test Caregiver',
      'phone': '+919876543210',
      'gender': 'female',
      'age': 30,
      'languages': ['hindi'],
      'highest_qualification': 'gda_non_nursing',
      'religion': 'hindu',
      'terms_accepted': true,
      'verification_status': 'available',
      'created_at': '2026-08-01T10:00:00Z',
    });
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
  await _settle(tester);
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
          _requirement(id: 'req-2', requirementNumber: 2, status: 'pending_review'),
        ],
      ),
    );

    expect(find.widgetWithText(ElevatedButton, 'Post a Requirement'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNotNull);
    expect(find.text('ORG-JOB-1'), findsOneWidget);
    expect(find.text('ORG-JOB-2'), findsOneWidget);
  });

  testWidgets('shows requirement details: type of nurse, duration, accommodation/food, special skills',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(requirements: [_requirement(durationType: 'long_term')]),
    );

    expect(find.text('Live — visible to caregivers'), findsOneWidget);
    expect(find.text('Registered Nurse'), findsOneWidget);
    expect(find.text('Long Term'), findsOneWidget);
    expect(find.text('Accommodation provided'), findsOneWidget);
    expect(find.text('No food'), findsOneWidget);
    expect(find.text('Wound care'), findsOneWidget);
  });

  testWidgets('highlights the status as a rounded, color-coded pill instead of plain text', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(requirements: [_requirement(status: 'active')]),
    );

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('Live — visible to caregivers'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(999));
    expect(decoration.border, isNotNull);
    expect(decoration.color, AppColors.success.withValues(alpha: 0.12));
  });

  testWidgets('shows the accepted caregiver on a closed requirement', (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'closed')],
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
    await _settle(tester);

    expect(repo.decidedRequirementId, 'req-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('rejecting an applicant requires a reason — Confirm stays disabled until something is typed',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await _settle(tester);

    final confirmButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Not enough experience');
    await _settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await _settle(tester);

    expect(repo.decidedRequirementId, 'req-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'rejected');
    expect(repo.decidedReason, 'Not enough experience');
  });

  testWidgets('a previously-rejected applicant can be re-accepted via "Accept Anyway"', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed')],
      applicationsByRequirementId: {
        'req-1': [_application(status: 'rejected')],
      },
    );
    await _pump(tester, repo);

    expect(find.widgetWithText(TextButton, 'Accept Anyway'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Accept Anyway'));
    await _settle(tester);

    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'accepted');
  });

  testWidgets('while one applicant is accepted, an undecided candidate offers no Accept/Reject action',
      (tester) async {
    await _pump(
      tester,
      _FakeOrganisationRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByRequirementId: {
          'req-1': [
            _application(id: 'app-1', status: 'accepted'),
            _application(id: 'app-2', status: 'applied'),
          ],
        },
      ),
    );

    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Accept Anyway'), findsNothing);
    // Only the accepted applicant's own Reject (undo) stays available.
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets('tapping View Profile on an undecided applicant opens their full profile', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await _settle(tester);

    expect(repo.profileFetchedRequirementId, 'req-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets('View Profile is also available for an already-decided (accepted) applicant', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed')],
      applicationsByRequirementId: {
        'req-1': [_application(status: 'accepted')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await _settle(tester);

    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets('disables the Post CTA and shows a message when job posting is blocked', (tester) async {
    await _pump(tester, _FakeOrganisationRepository(), isJobPostingBlocked: true);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Posting is currently blocked'), findsOneWidget);
  });

  testWidgets('shows Number of Vacancies, Preferred Gender, and Type of Nurse "Others" free text on the card',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [
        _requirement(
          typeOfNurse: 'others',
          typeOfNurseOther: 'Physiotherapist',
          numberOfVacancies: 7,
          preferredGender: 'female',
        ),
      ],
    );
    await _pump(tester, repo);

    expect(find.textContaining('Physiotherapist'), findsOneWidget);
    expect(find.text('Vacancies: 7'), findsOneWidget);
    expect(find.text('Preferred: Female'), findsOneWidget);
  });

  testWidgets(
      'the More options menu always offers exactly 4 actions: Edit, Post Similar, Cancel, Reactivate',
      (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Edit the Requirement'), findsOneWidget);
    expect(find.text('Post Similar Requirement'), findsOneWidget);
    expect(find.text('Cancel the Requirement'), findsOneWidget);
    expect(find.text('Reactivate the Requirement (Unavailable)'), findsOneWidget);
  });

  testWidgets('Edit the Requirement is disabled (locked) while there is an active (applied) application',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement()],
      applicationsByRequirementId: {
        'req-1': [_application(status: 'applied')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Edit the Requirement (Locked)'), findsOneWidget);
  });

  testWidgets(
      'a rejected or completed application locks editing too — ANY application at all locks it, not just an '
      'active applied/accepted one', (tester) async {
    for (final status in ['rejected', 'completed']) {
      final repo = _FakeOrganisationRepository(
        requirements: [_requirement()],
        applicationsByRequirementId: {
          'req-1': [_application(status: status)],
        },
      );
      await _pump(tester, repo);

      await tester.tap(find.byIcon(Icons.more_vert));
      await _settle(tester);

      expect(find.text('Edit the Requirement (Locked)'), findsOneWidget);
      expect(find.text('Edit the Requirement'), findsNothing);
    }
  });

  testWidgets('Cancel the Requirement is disabled once the requirement was admin-rejected', (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [
        _requirement(status: 'closed', rejectionReason: 'Not needed'),
      ],
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);

    expect(find.text('Cancel the Requirement (Unavailable)'), findsOneWidget);
  });

  testWidgets('Cancel the Requirement is disabled once already cancelled, and shows a Cancelled status',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [
        _requirement(status: 'closed', cancelledAt: '2026-08-05T10:00:00Z'),
      ],
    );
    await _pump(tester, repo);

    expect(find.text('Cancelled'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Cancel the Requirement (Unavailable)'), findsOneWidget);
    // Reactivate is the mirror image — disabled everywhere except once
    // actually cancelled.
    expect(find.text('Reactivate the Requirement'), findsOneWidget);
  });

  testWidgets('Reactivate the Requirement is disabled (Unavailable) for a live requirement', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    expect(find.text('Reactivate the Requirement (Unavailable)'), findsOneWidget);
  });

  testWidgets('tapping Reactivate the Requirement calls reactivateRequirement and reloads, no confirmation needed',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-05T10:00:00Z')],
    );
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Reactivate the Requirement'));
    await _settle(tester);

    expect(repo.reactivatedRequirementId, 'req-1');
  });

  testWidgets('shows the server error message if reactivating fails (e.g. JOB_010, job posting blocked)',
      (tester) async {
    final repo = _FakeOrganisationRepository(
      requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-05T10:00:00Z')],
    )..reactivateError = const ApiException(
        code: 'JOB_010', message: 'Your account is blocked from posting new requirements');
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Reactivate the Requirement'));
    await _settle(tester);

    expect(find.text('Your account is blocked from posting new requirements'), findsOneWidget);
  });

  testWidgets('confirming Cancel the Requirement calls cancelRequirement and reloads', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Cancel the Requirement'));
    await _settle(tester);

    expect(find.text('Cancel this requirement?'), findsOneWidget);
    await tester.tap(find.text('Yes, cancel it'));
    await _settle(tester);

    expect(repo.cancelledRequirementId, 'req-1');
  });

  testWidgets('cancelling the cancel-requirement confirmation dialog does not call cancelRequirement',
      (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Cancel the Requirement'));
    await _settle(tester);
    await tester.tap(find.text('No, keep it'));
    await _settle(tester);

    expect(repo.cancelledRequirementId, isNull);
  });

  testWidgets('tapping Edit the Requirement opens the edit screen pre-filled with current values', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement(typeOfNurse: 'auxiliary_nurse')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Edit the Requirement'));
    await _settle(tester);

    expect(find.text('Edit Requirement'), findsOneWidget);
    expect(find.text('Auxiliary Nurse'), findsOneWidget);
  });

  testWidgets('Post Similar Requirement is always enabled — no one-live limit like Individual', (tester) async {
    final repo = _FakeOrganisationRepository(requirements: [_requirement()]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await _settle(tester);
    await tester.tap(find.text('Post Similar Requirement'));
    await _settle(tester);

    expect(find.text('Post a Requirement'), findsOneWidget);
  });
}
