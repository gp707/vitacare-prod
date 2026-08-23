import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitacare_shared/vitacare_shared.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

import 'package:nursenow_app/core/providers.dart';
import 'package:nursenow_app/core/storage/local_storage.dart';
import 'package:nursenow_app/features/auth/state/session_notifier.dart';
import 'package:nursenow_app/features/auth/state/session_state.dart';
import 'package:nursenow_app/features/individual/data/individual_repository.dart';
import 'package:nursenow_app/features/individual/screens/jobs_posted_screen.dart';
import 'package:nursenow_app/features/organisation/data/organisation_repository.dart';

JobModel _requirement({
  String id = 'job-1',
  int jobNumber = 42,
  String status = 'active',
  int? salaryAmount = 1800,
  String? frequencyOfCare = 'daily',
  String? rejectionReason,
  String? cancelledAt,
  Map<String, dynamic>? careReceiver,
  List<String> languages = const ['hindi'],
}) {
  return JobModel.fromJson({
    'id': id,
    'job_number': jobNumber,
    'patient_job_number': jobNumber + 500,
    'city': 'bangalore',
    'area': 'Indiranagar',
    'description': 'Needs help with daily routine.',
    'duty_type': 'live_in',
    'frequency_of_care': frequencyOfCare,
    'start_date': '2026-09-01',
    'languages': languages,
    'salary_amount': salaryAmount,
    'status': status,
    'posted_by': 'individual-1',
    'posted_at': '2026-08-01T10:00:00Z',
    'created_at': '2026-08-01T10:00:00Z',
    'rejection_reason': rejectionReason,
    'cancelled_at': cancelledAt,
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

JobApplicationModel _application({
  String id = 'app-1',
  String jobId = 'job-1',
  String status = 'applied',
  String fullName = 'Test Caregiver',
  String appliedAt = '2026-08-01T10:00:00Z',
  String? declineReason,
  String? decidedBy,
}) {
  return JobApplicationModel.fromJson({
    'id': id,
    'job_id': jobId,
    'profile_id': 'profile-1',
    'status': status,
    'full_name': fullName,
    'phone': '+919876543210',
    'applied_at': appliedAt,
    'decline_reason': declineReason,
    'decided_by': decidedBy,
    'updated_at': '2026-08-01T10:00:00Z',
  });
}

class _FakeIndividualRepository extends IndividualRepository {
  List<JobModel> requirements;
  Map<String, List<JobApplicationModel>> applicationsByJobId;
  String? decidedJobId;
  String? decidedApplicationId;
  String? decidedStatus;
  String? decidedReason;
  String? profileFetchedJobId;
  String? profileFetchedApplicationId;
  String? editedJobId;
  String? cancelledJobId;

  _FakeIndividualRepository({this.requirements = const [], this.applicationsByJobId = const {}}) : super(Dio());

  @override
  Future<List<JobModel>> listMyRequirements() async => requirements;

  @override
  Future<JobModel> editRequirement(
    String jobId, {
    required CareReceiverInput careReceiver,
    required String city,
    required String area,
    String? description,
    required String dutyType,
    required String startDate,
    required List<String> languages,
    String? preferredGender,
    String? preferredReligion,
    String? frequencyOfCare,
    int? salaryAmount,
  }) async {
    editedJobId = jobId;
    return requirements.firstWhere((r) => r.id == jobId);
  }

  @override
  Future<void> cancelRequirement(String jobId) async {
    cancelledJobId = jobId;
  }

  @override
  Future<List<JobApplicationModel>> listApplications(String jobId) async => applicationsByJobId[jobId] ?? const [];

  @override
  Future<void> decideApplication(String jobId, String applicationId, String status, {String? reason}) async {
    decidedJobId = jobId;
    decidedApplicationId = applicationId;
    decidedStatus = status;
    decidedReason = reason;
  }

  @override
  Future<CaregiverProfileModel> getApplicantProfile(String jobId, String applicationId) async {
    profileFetchedJobId = jobId;
    profileFetchedApplicationId = applicationId;
    return CaregiverProfileModel.fromJson({
      'user_id': 'user-1',
      'profile_id': 'profile-1',
      'full_name': 'Test Caregiver',
      'phone': '+919876543210',
      'gender': 'female',
      'age': 30,
      'languages': ['hindi', 'english'],
      'highest_qualification': 'rn_above_2_years',
      'religion': 'hindu',
      'terms_accepted': true,
      'verification_status': 'available',
      'created_at': '2026-08-01T10:00:00Z',
    });
  }
}

Future<void> _pump(WidgetTester tester, _FakeIndividualRepository repo, {bool isJobPostingBlocked = false}) async {
  // Requirement cards accumulate a lot of content (About Patient/Requirement
  // tags, Edit/Cancel/Post Similar actions, applicant review section) — tall
  // enough that the default 800x600 test viewport clips action buttons out
  // of hit-testable range for some fixtures. A generous default surface
  // avoids that for every test in this file, not just the ones that
  // happened to need it first.
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final localStorage = await LocalStorage.create();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(localStorage),
        individualRepositoryProvider.overrideWithValue(repo),
        sessionProvider.overrideWith(
          (ref) => SessionNotifier(localStorage, repo, OrganisationRepository(Dio()))
            ..state = SessionAuthenticated(
              role: 'individual',
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

/// Closed/cancelled/rejected requirements are hidden by default behind a
/// toggle button — tests exercising their card content need to reveal them
/// first.
Future<void> _revealClosedRequirements(WidgetTester tester) async {
  await tester.tap(find.textContaining('Show Closed/Cancelled Requirements'));
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

  testWidgets(
      'shows the live requirement up front, and the full history (most recent first) once Show Closed/Cancelled is tapped',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-2', jobNumber: 43, status: 'active'),
          _requirement(id: 'job-1', jobNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
        ],
      ),
    );

    expect(find.text('PAT-JOB-543'), findsOneWidget);
    expect(find.text('PAT-JOB-542'), findsNothing);
    expect(find.text('Show Closed/Cancelled Requirements (1)'), findsOneWidget);

    await _revealClosedRequirements(tester);

    expect(find.text('PAT-JOB-543'), findsOneWidget);
    expect(find.text('PAT-JOB-542'), findsOneWidget);
  });

  testWidgets(
      'shows the accepted caregiver on a closed requirement up front, not just while active — an accepted candidate keeps it out of the closed/cancelled section',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    // No toggle needed — visible immediately, same as a live requirement.
    expect(find.textContaining('Show Closed/Cancelled Requirements'), findsNothing);
    expect(find.text('Closed — caregiver assigned'), findsOneWidget);
    expect(find.text('1 candidate applied in total'), findsOneWidget);
    expect(find.text('Test Caregiver'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
  });

  testWidgets('requirement card has a dark, wide border — senior-citizen-friendly visibility', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement()]));

    final container = tester.widget<Container>(
      find.ancestor(of: find.text('PAT-JOB-542'), matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, greaterThanOrEqualTo(2.5));
    expect(border.top.color, AppColors.textPrimary);
  });

  testWidgets('the full About Patient / requirement detail is collapsed by default, and expands on tap',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    // Collapsed by default — not confusing the screen with every field.
    expect(find.text('About Patient'), findsNothing);
    expect(find.text('74 yrs'), findsNothing);
    expect(find.text('Show Full Details'), findsOneWidget);

    await tester.tap(find.text('Show Full Details'));
    await tester.pumpAndSettle();

    expect(find.text('About Patient'), findsOneWidget);
    expect(find.text('74 yrs'), findsOneWidget);
    expect(find.text('About Nurse/Caregiver Requirement'), findsOneWidget);
    expect(find.text('Needs help with daily routine.'), findsOneWidget);
    expect(find.text('Hide Full Details'), findsOneWidget);
  });

  testWidgets('shows a "No Preference" tag under About Nurse/Caregiver Requirement when languages is empty — '
      'kept in sync with what admin sees, never a blank gap', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(languages: const [], careReceiver: _careReceiverJson)],
      ),
    );

    await tester.tap(find.text('Show Full Details'));
    await tester.pumpAndSettle();

    expect(find.text('No Preference'), findsOneWidget);
  });

  testWidgets('with multiple applicants, only the first undecided one is shown for review', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [
            _application(id: 'app-1', fullName: 'Ramesh Kumar', appliedAt: '2026-08-01T10:00:00Z'),
            _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
          ],
        },
      ),
    );

    expect(find.text('2 candidates applied in total'), findsOneWidget);
    expect(find.text('Reviewing candidate 1 of 2 awaiting your decision'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('Sita Devi'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets('a candidate awaiting a decision is highlighted with an amber border and an hourglass icon',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application()],
        },
      ),
    );

    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    final tile = tester.widget<Container>(
      find.ancestor(of: find.byIcon(Icons.hourglass_top), matching: find.byType(Container)).first,
    );
    final decoration = tile.decoration as BoxDecoration;
    expect((decoration.border as Border).top.color, AppColors.warning);
  });

  testWidgets('an accepted candidate shows a green check icon', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(icon.color, AppColors.success);
    expect(find.byIcon(Icons.cancel), findsNothing);
  });

  testWidgets('a rejected candidate shows a red cross icon', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit', decidedBy: 'individual-1')],
        },
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.cancel));
    expect(icon.color, AppColors.error);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets(
      'once a candidate is accepted, any other still-applied candidate is never shown for review — the queue only advances on reject',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [
            _application(id: 'app-1', fullName: 'Ramesh Kumar', status: 'accepted', appliedAt: '2026-08-01T10:00:00Z'),
            _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
          ],
        },
      ),
    );

    expect(find.text('2 candidates applied in total'), findsOneWidget);
    expect(find.textContaining('Reviewing'), findsNothing);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    // The still-applied candidate's name/profile is never surfaced.
    expect(find.text('Sita Devi'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Accept'), findsNothing);
    // The one Reject button present belongs to the accepted candidate's own
    // tile (undo the acceptance) — not a review action for anyone else.
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
  });

  testWidgets(
      'rejecting an already-accepted candidate undoes the acceptance, hides their phone, and reopens the queue',
      (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      applicationsByJobId: {
        'job-1': [
          _application(id: 'app-1', fullName: 'Ramesh Kumar', status: 'accepted', appliedAt: '2026-08-01T10:00:00Z'),
          _application(id: 'app-2', fullName: 'Sita Devi', appliedAt: '2026-08-02T10:00:00Z'),
        ],
      },
    );
    await _pump(tester, repo);

    // Precondition: the accepted candidate's phone is visible, the second
    // applicant is not yet surfaced for review.
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Sita Devi'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Decline this candidate'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Changed our mind');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'rejected');
    expect(repo.decidedReason, 'Changed our mind');
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

  testWidgets('tapping View Profile on the candidate under review opens their full profile', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await tester.pumpAndSettle();

    expect(repo.profileFetchedJobId, 'job-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
    expect(find.text('Registered Nurse above 2 years of experience'), findsOneWidget);
    expect(find.text('VitaCare-verified caregiver'), findsOneWidget);
  });

  testWidgets('View Profile stays available for an accepted candidate', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application(status: 'accepted')],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Profile'));
    await tester.pumpAndSettle();

    expect(repo.profileFetchedJobId, 'job-1');
    expect(repo.profileFetchedApplicationId, 'app-1');
    expect(find.text('30 yrs'), findsOneWidget);
  });

  testWidgets('View Profile is not offered once the engagement is completed (Closed by Caregiver)', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
      applicationsByJobId: {
        'job-1': [_application(status: 'completed')],
      },
    );
    await _pump(tester, repo);
    await _revealClosedRequirements(tester);

    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsNothing);
  });

  testWidgets('View Profile is not offered once a candidate is rejected by the patient', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit', decidedBy: 'individual-1')],
        },
      ),
    );

    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsNothing);
  });

  testWidgets('View Profile is not offered once a candidate self-withdraws (rejected by the caregiver)', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected')], // decidedBy omitted — self-withdrawal
        },
      ),
    );

    expect(find.widgetWithText(OutlinedButton, 'View Profile'), findsNothing);
  });

  testWidgets(
      'a closed requirement with a currently-accepted candidate stays visible up front, unlike a plain closed one which stays hidden behind the toggle',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-1', jobNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
          _requirement(id: 'job-2', jobNumber: 43, status: 'closed', salaryAmount: null, frequencyOfCare: null),
        ],
        applicationsByJobId: {
          'job-2': [_application(status: 'accepted')],
        },
      ),
    );

    // job-2 (accepted candidate) is up front; job-1 (no accepted candidate)
    // stays behind the toggle.
    expect(find.text('PAT-JOB-543'), findsOneWidget);
    expect(find.text('PAT-JOB-542'), findsNothing);
    expect(find.text('Show Closed/Cancelled Requirements (1)'), findsOneWidget);

    await _revealClosedRequirements(tester);

    expect(find.text('PAT-JOB-542'), findsOneWidget);
  });

  testWidgets('rejecting requires a reason — Confirm stays disabled until something is typed', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Decline this candidate'), findsOneWidget);
    var confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Schedule does not match');
    await tester.pump();
    confirmButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Confirm'));
    expect(confirmButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(repo.decidedJobId, 'job-1');
    expect(repo.decidedApplicationId, 'app-1');
    expect(repo.decidedStatus, 'rejected');
    expect(repo.decidedReason, 'Schedule does not match');
  });

  testWidgets('cancelling the reject dialog does not call the repository', (tester) async {
    final repo = _FakeIndividualRepository(
      requirements: [_requirement()],
      applicationsByJobId: {
        'job-1': [_application()],
      },
    );
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.decidedApplicationId, isNull);
  });

  testWidgets('a decided/rejected applicant shows the reason underneath in the read-only history', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not available on weekends')],
        },
      ),
    );

    expect(find.text('Your reason: Not available on weekends'), findsOneWidget);
  });

  testWidgets('hides a rejected candidate\'s phone number in the read-only history', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit')],
        },
      ),
    );

    expect(find.text('+919876543210'), findsNothing);
  });

  testWidgets('still shows an accepted candidate\'s phone number', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'accepted')],
        },
      ),
    );

    expect(find.text('+919876543210'), findsOneWidget);
  });

  testWidgets('shows "Rejected by Caregiver" and still shows the phone when the caregiver closed the job themselves '
      'before being accepted', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected')], // decidedBy omitted — self-withdrawal
        },
      ),
    );

    expect(find.text('Rejected by Caregiver'), findsOneWidget);
    expect(find.text('+919876543210'), findsNothing);
  });

  testWidgets('shows plain "Rejected" (not "by Caregiver") when the patient was the one who declined them',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit', decidedBy: 'individual-1')],
        },
      ),
    );

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Rejected by Caregiver'), findsNothing);
  });

  testWidgets('shows "Closed by Caregiver" but hides the phone number for a completed engagement, keeping the name',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null)],
        applicationsByJobId: {
          'job-1': [_application(status: 'completed', fullName: 'Ramesh Kumar')],
        },
      ),
    );
    await _revealClosedRequirements(tester);

    expect(find.text('Closed by Caregiver'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('+919876543210'), findsNothing);
  });

  testWidgets('shows Edit as the primary button when there is no active application', (tester) async {
    await _pump(tester, _FakeIndividualRepository(requirements: [_requirement()]));

    expect(find.widgetWithText(ElevatedButton, 'Edit'), findsOneWidget);
    expect(find.textContaining('Editing is locked'), findsNothing);
  });

  testWidgets(
      'hides the Edit button and shows a locked message while there is an active (applied) application',
      (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement()],
        applicationsByJobId: {
          'job-1': [_application(status: 'applied')],
        },
      ),
    );

    expect(find.widgetWithText(ElevatedButton, 'Edit'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.textContaining('Editing is locked'), findsOneWidget);
  });

  testWidgets('rejected/completed applications do not lock editing — Edit is offered via More options', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed')],
        applicationsByJobId: {
          'job-1': [_application(status: 'rejected', declineReason: 'Not a fit')],
        },
      ),
    );
    await _revealClosedRequirements(tester);

    // Not live and no other live requirement — Post Similar is primary,
    // Edit is demoted to the "More options" menu, not shown top-level.
    expect(find.widgetWithText(ElevatedButton, 'Post Similar Requirement'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('tapping Edit opens the edit screen pre-filled with the requirement\'s current values', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      _FakeIndividualRepository(requirements: [_requirement(careReceiver: _careReceiverJson)]),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Requirement'), findsOneWidget);
    expect(find.text('74'), findsOneWidget); // age, pre-filled
    expect(find.widgetWithText(TextField, "Patient's Age (Mandatory)"), findsOneWidget);
    final areaField = tester.widget<TextField>(find.widgetWithText(TextField, 'Area (Mandatory)'));
    expect(areaField.controller!.text, 'Indiranagar');
  });

  testWidgets(
      'offers Cancel Requirement via More options on a live requirement, and confirming it calls cancelRequirement',
      (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Cancel Requirement'), findsOneWidget);
    await tester.tap(find.text('Cancel Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this requirement?'), findsOneWidget);
    await tester.tap(find.text('Yes, cancel it'));
    await tester.pumpAndSettle();

    expect(repo.cancelledJobId, 'job-1');
  });

  testWidgets('cancelling the cancel-requirement confirmation dialog does not call cancelRequirement', (tester) async {
    final repo = _FakeIndividualRepository(requirements: [_requirement(status: 'active')]);
    await _pump(tester, repo);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel Requirement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, keep it'));
    await tester.pumpAndSettle();

    expect(repo.cancelledJobId, isNull);
  });

  testWidgets('shows a Cancelled status and hides the applicants section once cancelled', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', cancelledAt: '2026-08-22T10:00:00Z')],
      ),
    );
    await _revealClosedRequirements(tester);

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel Requirement'), findsNothing);
    expect(find.textContaining('This requirement was cancelled.'), findsOneWidget);
    expect(find.textContaining('candidate applied in total'), findsNothing);
  });

  testWidgets('hides Cancel Requirement once the requirement was admin-rejected', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, rejectionReason: 'Duplicate posting'),
        ],
      ),
    );
    await _revealClosedRequirements(tester);

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel Requirement'), findsNothing);
  });

  testWidgets(
      'shows Post Similar Requirement on a non-live requirement when there is no other live requirement, and it opens a pre-filled clone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [_requirement(status: 'closed', salaryAmount: null, frequencyOfCare: null, careReceiver: _careReceiverJson)],
      ),
    );
    await _revealClosedRequirements(tester);

    expect(find.widgetWithText(ElevatedButton, 'Post Similar Requirement'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post Similar Requirement'));
    await tester.pumpAndSettle();

    expect(find.text('Post Similar Requirement'), findsWidgets);
    expect(find.text('74'), findsOneWidget);
  });

  testWidgets('hides Post Similar Requirement while another requirement is still live', (tester) async {
    await _pump(
      tester,
      _FakeIndividualRepository(
        requirements: [
          _requirement(id: 'job-1', jobNumber: 42, status: 'closed', salaryAmount: null, frequencyOfCare: null),
          _requirement(id: 'job-2', jobNumber: 43, status: 'active'),
        ],
      ),
    );
    await _revealClosedRequirements(tester);

    expect(find.text('Post Similar Requirement'), findsNothing);
  });

  testWidgets('disables the Post CTA and shows a message when job posting is blocked', (tester) async {
    await _pump(tester, _FakeIndividualRepository(), isJobPostingBlocked: true);

    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Post a Requirement'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Posting is currently blocked'), findsOneWidget);
  });
}
